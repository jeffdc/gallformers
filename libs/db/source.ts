import { Prisma, source } from '@prisma/client';
import { pipe } from 'fp-ts/lib/function';
import * as TE from 'fp-ts/lib/TaskEither';
import { TaskEither } from 'fp-ts/lib/TaskEither';
import { DeleteResult, SourceApi, SourceUpsertFields, SourceWithSpeciesApi, SourceWithSpeciesSourceApi } from '../api/apitypes';
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

export const sourceById = (id: number): TaskEither<Error, SourceWithSpeciesApi[]> => {
    const sources = () =>
        db.source.findMany({
            include: {
                speciessource: {
                    include: {
                        species: {
                            select: {
                                id: true,
                                name: true,
                                taxoncode: true,
                            },
                        },
                    },
                },
            },
            where: { id: { equals: id } },
        });

    // eslint-disable-next-line prettier/prettier
    return pipe(
        TE.tryCatch(sources, handleError),
        TE.map((sources) =>
            sources.map((s) => ({
                ...s,
                species: s.speciessource.map((spsp) => ({ ...spsp.species, taxoncode: spsp.species.taxoncode ?? '' })),
            })),
        ),
    );
};

export const allSources = (): TaskEither<Error, source[]> => {
    const sources = () =>
        db.source.findMany({
            orderBy: { title: 'asc' },
        });

    return TE.tryCatch(sources, handleError);
};

export const allSourcesWithSpecies = (): TaskEither<Error, SourceWithSpeciesApi[]> => {
    const sources = () =>
        db.source.findMany({
            include: {
                speciessource: {
                    include: {
                        species: {
                            select: { id: true, name: true, taxoncode: true },
                        },
                    },
                },
            },
        });

    return pipe(
        TE.tryCatch(sources, handleError),
        TE.map((sos) =>
            sos.map((s) => ({
                ...s,
                species: s.speciessource.map((spso) => ({
                    ...spso.species,
                    taxoncode: spso.species.taxoncode ? spso.species.taxoncode : '',
                })),
            })),
        ),
    );
};

export const allSourceIds = (): TaskEither<Error, string[]> => {
    const ids = () => db.source.findMany({ select: { id: true } });

    // eslint-disable-next-line prettier/prettier
    return pipe(
        TE.tryCatch(ids, handleError),
        TE.map((i) => i.map(extractId).map((x) => x.toString())),
    );
};

export const sourcesWithSpeciesSourceBySpeciesId = (speciesId: number): TaskEither<Error, SourceWithSpeciesSourceApi[]> => {
    const sources = () =>
        db.source.findMany({
            include: { speciessource: true },
            where: { speciessource: { some: { species_id: { equals: speciesId } } } },
        });

    // eslint-disable-next-line prettier/prettier
    return pipe(
        TE.tryCatch(sources, handleError),
        TE.map((d) => {
            return d;
        }),
        TE.map((t) => adaptMany(t)),
        TE.map((t) => t as SourceWithSpeciesSourceApi[]), // kludge... :(
    );
};

export const deleteSource = (id: number): TaskEither<Error, DeleteResult> => {
    // have to make raw call since Prisma does not handle cascade delete:  https://github.com/prisma/prisma/issues/2057
    const sql = `DELETE FROM source WHERE id = ${id}`;
    const doDelete = () => db.$executeRaw(Prisma.sql([sql]));

    const toDeleteResult = (count: number): DeleteResult => {
        return {
            type: 'source',
            name: id.toString(),
            count: count,
        };
    };

    // eslint-disable-next-line prettier/prettier
    return pipe(
        TE.tryCatch(doDelete, handleError),
        TE.map(toDeleteResult),
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
                datacomplete: source.datacomplete,
                license: source.license,
                licenselink: source.licenselink,
            },
            create: {
                author: source.author,
                citation: source.citation,
                link: source.link,
                pubyear: source.pubyear,
                title: source.title,
                datacomplete: source.datacomplete,
                license: source.license,
                licenselink: source.licenselink,
            },
        });

    // eslint-disable-next-line prettier/prettier
    return pipe(
        TE.tryCatch(upsert, handleError),
        TE.map(adaptor),
    );
};

export const searchSources = (s: string): TaskEither<Error, SourceApi[]> => {
    return pipe(
        TE.tryCatch(
            () =>
                db.source.findMany({
                    where: { title: { contains: s } },
                    orderBy: { title: 'asc' },
                }),
            handleError,
        ),
    );
};
