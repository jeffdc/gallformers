import { Prisma } from '@prisma/client';
import { pipe } from 'fp-ts/lib/function';
import * as TE from 'fp-ts/lib/TaskEither';
import { TaskEither } from 'fp-ts/lib/TaskEither';
import { DeleteResult, HostApi, HostSimple, SpeciesUpsertFields } from '../apitypes';
import { ExtractTFromPromise, handleError } from '../utils/util';
import db from './db';
import { HostTaxon } from './dbinternaltypes';
import { mightBeNull } from './utils';

/**
 * Fetches all hosts.
 */
export const allHosts = (): TaskEither<Error, HostApi[]> => {
    return getHosts();
};

/**
 * Fetches all hosts into a HostSimple format.
 */
export const allHostsSimple = (): TaskEither<Error, HostSimple[]> => {
    const simplify = (hosts: HostApi[]) =>
        hosts.map((h) => {
            return {
                name: h.name,
                id: h.id,
                commonnames: mightBeNull(h?.commonnames),
                synonyms: mightBeNull(h?.synonyms),
            };
        });

    return pipe(allHosts(), TE.map(simplify));
};

/**
 * Fetches all host names as a string[].
 */
export const allHostNames = (): TaskEither<Error, string[]> => {
    return pipe(
        allHosts(),
        TE.map((hosts) => hosts.map((h) => h.name)),
    );
};

/**
 * Fetches all of the Genera for the hosts.
 */
export const allHostGenera = (): TaskEither<Error, string[]> => {
    const genera = () =>
        db.species.findMany({
            select: {
                genus: true,
            },
            distinct: [Prisma.SpeciesDistinctFieldEnum.genus],
            where: { taxoncode: { equals: HostTaxon } },
            orderBy: { genus: 'asc' },
        });

    return pipe(
        TE.tryCatch(genera, handleError),
        TE.map((hosts) => hosts.map((h) => h.genus)),
    );
};

export const allHostIds = (): TaskEither<Error, string[]> => {
    const hosts = () =>
        db.species.findMany({
            select: { id: true },
            where: { taxoncode: { equals: 'plant' } },
        });

    return pipe(
        TE.tryCatch(hosts, handleError),
        TE.map((hosts) => hosts.map((h) => h.id.toString())),
    );
};

/**
 * A general way to fetch hosts. Check this file for pre-defined helpers that are easier to use.
 * @param whereClause a where clause by which to filter galls
 */
export const getHosts = (
    whereClause: readonly Prisma.speciesWhereInput[] = [],
    operatorAnd = true,
    distinct: Prisma.SpeciesDistinctFieldEnum[] = ['id'],
): TaskEither<Error, HostApi[]> => {
    const w = operatorAnd
        ? { AND: [...whereClause, { taxoncode: { equals: HostTaxon } }] }
        : { AND: [{ taxoncode: { equals: HostTaxon } }, { OR: whereClause }] };

    const hosts = () =>
        db.species.findMany({
            include: {
                abundance: true,
                family: true,
                host_galls: {
                    include: {
                        gallspecies: {
                            select: { id: true, name: true },
                        },
                    },
                },
                speciessource: {
                    include: {
                        source: true,
                    },
                },
            },
            where: w,
            distinct: distinct,
            orderBy: { name: 'asc' },
        });

    type DBHost = ExtractTFromPromise<ReturnType<typeof hosts>>;

    // we want a stronger non-null contract on what we return then is modelable in the DB
    const clean = (hosts: DBHost): HostApi[] =>
        hosts.flatMap((h) => {
            // set the default description to make the caller's life easier
            const d = h.speciessource.find((s) => s.useasdefault === 1)?.description;
            const newh = {
                ...h,
                description: d ? d : '',
                // remove the indirection of the many-to-many table for easier usage
                hosts: h.host_galls.map((h) => {
                    return {
                        // due to prisma problems we had to make these hostspecies relationships optional, however
                        // if we are here then there must be a record in the host table so it can not be null :(
                        id: h.gallspecies?.id,
                        name: h.gallspecies?.name,
                    };
                }),
            };
            return newh as HostApi; // ugh, TS type-checker can not "see" that we eliminated the null.
        });

    return pipe(TE.tryCatch(hosts, handleError), TE.map(clean));
};

/**
 * Fetch a host by its ID.
 * @param id
 */
export const hostById = (id: number): TaskEither<Error, HostApi[]> => {
    return getHosts([{ id: id }]);
};

export const upsertHost = (h: SpeciesUpsertFields): TaskEither<Error, number> => {
    const abundanceConnect = () => {
        if (h.abundance) {
            return { connect: { abundance: h.abundance } };
        } else {
            return {};
        }
    };

    const upsert = () =>
        db.species.upsert({
            where: { name: h.name },
            update: {
                family: { connect: { name: h.family } },
                abundance: { connect: { abundance: h.abundance } },
                synonyms: h.synonyms,
                commonnames: h.commonnames,
            },
            create: {
                name: h.name,
                genus: h.name.split(' ')[0],
                taxontype: { connect: { taxoncode: HostTaxon } },
                family: { connect: { name: h.family } },
                abundance: abundanceConnect(),
                synonyms: h.synonyms,
                commonnames: h.commonnames,
            },
        });

    return pipe(
        TE.tryCatch(upsert, handleError),
        TE.map((sp) => sp.id),
    );
};

export const getIdsFromHostSpeciesIds = (speciesIds: number[]): TaskEither<Error, number[]> => {
    const hostIds = () =>
        db.host.findMany({
            where: { host_species_id: { in: speciesIds } },
        });

    return pipe(
        TE.tryCatch(hostIds, handleError),
        TE.map((hostIds) => hostIds.map((h) => h.id)),
    );
};

/**
 * The steps required to delete a Host. This is a hack to fake CASCADE DELETE since Prisma does not support it yet.
 * See: https://github.com/prisma/prisma/issues/2057
 * @param speciesids an array of ids of the species (host) to delete
 */
export const hostDeleteSteps = (speciesids: number[]): Promise<Prisma.BatchPayload>[] => {
    return [
        db.host.deleteMany({
            where: { gall_species_id: { in: speciesids } },
        }),

        db.speciessource.deleteMany({
            where: { species_id: { in: speciesids } },
        }),

        db.species.deleteMany({
            where: { id: { in: speciesids } },
        }),
    ];
};

export const deleteHost = (speciesid: number): TaskEither<Error, DeleteResult> => {
    const deleteHostTx = (speciesid: number) => TE.tryCatch(() => db.$transaction(hostDeleteSteps([speciesid])), handleError);

    const toDeleteResult = (batch: Prisma.BatchPayload[]): DeleteResult => {
        return {
            type: 'host',
            name: '',
            count: batch.reduce((acc, v) => acc + v.count, 0),
        };
    };

    // eslint-disable-next-line prettier/prettier
    return pipe(
        deleteHostTx(speciesid),
        TE.map(toDeleteResult)
    );
};
