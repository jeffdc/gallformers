import { Prisma, source } from '@prisma/client';
import { TaskEither } from 'fp-ts/lib/TaskEither';
import * as TE from 'fp-ts/lib/TaskEither';
import db from './db';
import { handleError } from '../utils/util';
import { extractId } from './utils';
import { pipe } from 'fp-ts/lib/function';
import { DeleteResult, SourceUpsertFields } from '../apitypes';

export const sourceById = (id: number): TaskEither<Error, source[]> => {
    const sources = () =>
        db.source.findMany({
            where: { id: { equals: id } },
        });

    return TE.tryCatch(sources, handleError);
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

export const upsertSource = (source: SourceUpsertFields): TaskEither<Error, number> => {
    const upsert = () =>
        db.source.upsert({
            where: { title: source.title },
            update: {
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

    return pipe(
        TE.tryCatch(upsert, handleError),
        TE.map((s) => s.id),
    );
};
