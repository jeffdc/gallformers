import { Prisma, source } from '@prisma/client';
import { pipe } from 'fp-ts/lib/function';
import * as TE from 'fp-ts/lib/TaskEither';
import { TaskEither } from 'fp-ts/lib/TaskEither';
import { DeleteResult, SourceApi, SourceUpsertFields, SourceWithSpeciesSourceApi } from '../api/apitypes';
import { isOfType } from '../utils/types';
import { handleError } from '../utils/util';
import db from './db';
import { extractId } from './utils';

const adaptor = <T extends source>(source: T): SourceApi | SourceWithSpeciesSourceApi =>
    isOfType(source, 'speciessource' as keyof SourceWithSpeciesSourceApi)
        ? {
              ...source,
              speciessource: source.speciessource,
          }
        : {
              ...source,
          };

const adaptMany = <T extends source>(sources: T[]): (SourceApi | SourceWithSpeciesSourceApi)[] => sources.map(adaptor);

export const sourceById = (id: number): TaskEither<Error, SourceApi[]> => {
    const sources = () =>
        db.source.findMany({
            where: { id: { equals: id } },
        });

    // eslint-disable-next-line prettier/prettier
    return pipe(
        TE.tryCatch(sources, handleError),
        TE.map(adaptMany),
    );
};

export const allSources = (): TaskEither<Error, source[]> => {
    const sources = () =>
        db.source.findMany({
            orderBy: { title: 'asc' },
        });

    return TE.tryCatch(sources, handleError);
};

export const allSourceIds = (): TaskEither<Error, string[]> => {
    const ids = () => db.source.findMany({ select: { id: true } });

    // eslint-disable-next-line prettier/prettier
    return pipe(
        TE.tryCatch(ids, handleError),
        TE.map((i) => i.map(extractId).map((x) => x.toString())),
    );
};

export const sourcesWithSpecieSourceBySpeciesId = (speciesId: number): TaskEither<Error, SourceWithSpeciesSourceApi[]> => {
    const sources = () =>
        db.source.findMany({
            include: { speciessource: true },
            where: { speciessource: { some: { species_id: speciesId } } },
        });

    // eslint-disable-next-line prettier/prettier
    return pipe(
        TE.tryCatch(sources, handleError),
        TE.map(adaptMany),
        TE.map((t) => t as SourceWithSpeciesSourceApi[]), // kludge... :(
    );
};

/**
 * The steps required to delete a Source. This is a hack to fake CASCADE DELETE since Prisma does not support it yet.
 * See: https://github.com/prisma/prisma/issues/2057
 * @param sourceids an array of ids of the species (host) to delete
 */
export const sourceDeleteSteps = (sourceids: number[]): Promise<Prisma.BatchPayload>[] => {
    return [
        db.speciessource.deleteMany({
            where: { source_id: { in: sourceids } },
        }),

        db.source.deleteMany({
            where: { id: { in: sourceids } },
        }),
    ];
};

export const deleteSource = (id: number): TaskEither<Error, DeleteResult> => {
    const deleteSourceTx = (sourceid: number) => TE.tryCatch(() => db.$transaction(sourceDeleteSteps([sourceid])), handleError);

    const toDeleteResult = (batch: Prisma.BatchPayload[]): DeleteResult => {
        return {
            type: 'source',
            name: '',
            count: batch.reduce((acc, v) => acc + v.count, 0),
        };
    };

    // eslint-disable-next-line prettier/prettier
    return pipe(
        deleteSourceTx(id),
        TE.map(toDeleteResult)
    );
};

export const upsertSource = (source: SourceUpsertFields): TaskEither<Error, SourceApi> => {
    const upsert = () =>
        db.source.upsert({
            where: { id: source.id },
            update: {
                title: source.title,
                author: source.author,
                citation: source.citation,
                link: source.link,
                pubyear: source.pubyear,
            },
            create: {
                author: source.author,
                citation: source.citation,
                link: source.link,
                pubyear: source.pubyear,
                title: source.title,
            },
        });

    // eslint-disable-next-line prettier/prettier
    return pipe(
        TE.tryCatch(upsert, handleError),
        TE.map(adaptor),
    );
};
