import {
    abundance,
    alias,
    aliasspecies,
    host,
    image,
    place,
    Prisma,
    PrismaPromise,
    source,
    species,
    speciesplace,
    speciessource,
} from '@prisma/client';
import * as A from 'fp-ts/lib/Array';
import { constant, flow, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import * as TE from 'fp-ts/lib/TaskEither';
import { TaskEither } from 'fp-ts/lib/TaskEither';
import {
    DeleteResult,
    HostApi,
    HostSimple,
    HostTaxon,
    SimpleSpecies,
    SpeciesApi,
    SpeciesUpsertFields,
    SpeciesWithPlaces,
} from '../api/apitypes';
import { FGS, GENUS, SECTION } from '../api/taxonomy';
import { deleteImagesBySpeciesId } from '../images/images';
import { ExtractTFromPromise } from '../utils/types';
import { handleError, hasProp, optionalWith } from '../utils/util';
import db from './db';
import { adaptImage } from './images';
import {
    adaptAbundance,
    speciesCreateData,
    speciesTaxonomyAdditionalUpdateSteps,
    speciesUpdateData,
    updateAbundance,
} from './species';
import { taxonomyForSpecies } from './taxonomy';

type DBHost = species & {
    abundance: abundance | null;
    host_galls: (host & {
        gallspecies: {
            id: number;
            name: string;
        } | null;
    })[];
    speciessource: (speciessource & {
        source: source;
    })[];
    aliasspecies: (aliasspecies & {
        alias: alias;
    })[];
    image: (image & {
        source:
            | (source & {
                  speciessource: speciessource[];
              })
            | null;
    })[];
    fgs: FGS;
    places: (speciesplace & {
        place: place;
    })[];
};

// we want a stronger non-null contract on what we return then is modelable in the DB
const adaptor = (hosts: readonly DBHost[]): HostApi[] =>
    hosts.flatMap((h) => {
        // set the default description to make the caller's life easier
        const d = h.speciessource.find((s) => s.useasdefault === 1)?.description;
        const newh: HostApi = {
            id: h.id,
            name: h.name,
            datacomplete: h.datacomplete,
            description: O.fromNullable(d),
            taxoncode: h.taxoncode ? h.taxoncode : '',
            abundance: optionalWith(h.abundance, adaptAbundance),
            speciessource: h.speciessource,
            // remove the indirection of the many-to-many table for easier usage
            galls: h.host_galls.map((h) => {
                // due to prisma problems we had to make these hostspecies relationships optional, however
                // if we are here then there must be a record in the host table so it can not be null :(
                if (!h.gallspecies?.id || !h.gallspecies?.name) throw new Error('Invalid state for hosts.');
                return {
                    id: h.gallspecies?.id,
                    name: h.gallspecies?.name,
                };
            }),
            images: h.image.map(adaptImage),
            aliases: h.aliasspecies.map((a) => ({
                ...a.alias,
            })),
            fgs: h.fgs,
            places: h.places.map((p) => ({
                ...p.place,
            })),
        };
        return newh;
    });

/**
 * Fetch all hosts.
 */
export const allHosts = (): TaskEither<Error, HostApi[]> => getHosts();

export const allHostsWithPlaces = (): TaskEither<Error, SpeciesWithPlaces[]> => {
    const getHostsWithPlaces = () =>
        db.species.findMany({
            where: { taxoncode: { equals: HostTaxon } },
            select: {
                id: true,
                name: true,
                places: {
                    include: { place: true },
                },
            },
        });

    const simplify = (hosts: ExtractTFromPromise<ReturnType<typeof getHostsWithPlaces>>): SpeciesWithPlaces[] =>
        hosts.map((h) => {
            return {
                ...h,
                taxoncode: HostTaxon,
                places: h.places.map((p) => p.place),
            };
        });

    return pipe(TE.tryCatch(getHostsWithPlaces, handleError), TE.map(simplify));
};

/**
 * Fetch all hosts into a HostSimple format.
 */
export const allHostsSimple = (): TaskEither<Error, HostSimple[]> => {
    // if we call allHosts() the performance is quite poor so this is an optimized version that minimizes the data fetched
    const getSimpleHosts = () =>
        db.species.findMany({
            where: { taxoncode: { equals: HostTaxon } },
            select: {
                id: true,
                name: true,
                aliasspecies: { include: { alias: true } },
                datacomplete: true,
                places: { include: { place: true } },
            },
        });

    const simplify = (hosts: ExtractTFromPromise<ReturnType<typeof getSimpleHosts>>): HostSimple[] =>
        hosts.map((h) => {
            return {
                ...h,
                aliases: h.aliasspecies.map((a) => a.alias),
                places: h.places.map((p) => p.place),
            };
        });

    return pipe(TE.tryCatch(getSimpleHosts, handleError), TE.map(simplify));
};

/**
 * Fetch all host names as a string[].
 */
export const allHostNames = (): TaskEither<Error, string[]> =>
    pipe(
        allHosts(),
        TE.map((hosts) => hosts.map((h) => h.name)),
    );

/**
 * Fetch all the ids for the hosts.
 * @returns
 */
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
    whereClause: Prisma.speciesWhereInput[] = [],
    operatorAnd = true,
    distinct: Prisma.SpeciesScalarFieldEnum[] = ['id'],
): TaskEither<Error, HostApi[]> => {
    const w = operatorAnd
        ? { AND: [...whereClause, { taxoncode: { equals: HostTaxon } }] }
        : { AND: [{ taxoncode: { equals: HostTaxon } }, { OR: whereClause }] };

    const hosts = () =>
        db.species.findMany({
            include: {
                abundance: true,
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
                image: { include: { source: { include: { speciessource: true } } } },
                aliasspecies: { include: { alias: true } },
                places: { include: { place: true } },
            },
            where: w,
            distinct: distinct,
            orderBy: { name: 'asc' },
        });

    return pipe(
        TE.tryCatch(hosts, handleError),
        TE.map(
            flow(
                A.map((h) =>
                    pipe(
                        taxonomyForSpecies(h.id),
                        TE.map((fgs) => ({ ...h, fgs: fgs } as DBHost)),
                    ),
                ),
            ),
        ),
        TE.map(TE.sequenceArray),
        TE.flatten,
        TE.map(adaptor),
    );
};

/**
 * Fetch a host by its ID.
 * @param id
 */
export const hostById = (id: number): TaskEither<Error, HostApi[]> => getHosts([{ id: id }]);

/**
 * Fetch a host by its name.
 * @param name
 */
export const hostByName = (name: string): TaskEither<Error, HostApi[]> => getHosts([{ name: name }]);

/**
 * Fetch all hosts for the given genus.
 * @param genus
 * @returns
 */
export const hostsByGenus = (genus: string): TaskEither<Error, HostApi[]> => {
    if (!genus || genus.length === 0) return TE.taskEither.of([]);

    return getHosts([
        {
            speciestaxonomy: {
                some: {
                    taxonomy: { AND: [{ name: { equals: genus } }, { type: { equals: GENUS } }] },
                },
            },
        },
    ]);
};

/////////////////////////////////////////
const upsertSection = (host: SpeciesUpsertFields) => {
    return pipe(
        host.fgs.section,
        O.map((s) =>
            db.speciestaxonomy.create({
                data: { species_id: host.id, taxonomy_id: s.id },
            }),
        ),
        O.getOrElseW(constant(db.speciestaxonomy.count({ where: { species_id: -1 } }))),
    );
};

const hostUpdateSteps = (host: SpeciesUpsertFields): PrismaPromise<unknown>[] => {
    return [
        db.species.update({
            where: { id: host.id },
            data: {
                ...speciesUpdateData(host),
            },
        }),
        updateAbundance(host.id, host.abundance),
        ...speciesTaxonomyAdditionalUpdateSteps(host),
        db.speciestaxonomy.deleteMany({
            where: { AND: [{ species_id: host.id }, { taxonomy: { type: { equals: SECTION } } }] },
        }),
        // deal with a possible change to Section, added, changed, deleted
        upsertSection(host),
    ];
};

const hostCreate = (host: SpeciesUpsertFields): PrismaPromise<unknown>[] => {
    return [
        db.species.create({
            data: {
                ...speciesCreateData(host),
                taxontype: { connect: { taxoncode: HostTaxon } },
            },
        }),
    ];
};

/**
 * Update or insert a host.
 * @param h
 * @returns
 */
export const upsertHost = (h: SpeciesUpsertFields): TaskEither<Error, SpeciesApi> => {
    const updateHostTx = TE.tryCatch(() => db.$transaction(hostUpdateSteps(h)), handleError);
    const createHostTx = TE.tryCatch(() => db.$transaction(hostCreate(h)), handleError);

    const getHost = () => {
        return hostByName(h.name);
    };

    // eslint-disable-next-line prettier/prettier
    return pipe(
        h.id < 0 ? createHostTx : updateHostTx,
        TE.chain(getHost),
        TE.fold(
            (e) => TE.left(e),
            (s) => (s.length <= 0 ? TE.left(new Error('Failed to get upserted data.')) : TE.right(s[0])),
        ),
    );
};

/**
 * The steps required to delete a Host. This is a hack to fake CASCADE DELETE since Prisma does not support it yet.
 * See: https://github.com/prisma/prisma/issues/2057
 * @param speciesids an array of ids of the species (host) to delete
 */
const hostDeleteSteps = (speciesids: number[]): PrismaPromise<Prisma.BatchPayload | number>[] => {
    return [
        db.host.deleteMany({
            where: { host_species_id: { in: speciesids } },
        }),

        db.speciesplace.deleteMany({
            where: { species_id: { in: speciesids } },
        }),

        db.speciessource.deleteMany({
            where: { species_id: { in: speciesids } },
        }),

        db.aliasspecies.deleteMany({
            where: { species_id: { in: speciesids } },
        }),

        db.speciestaxonomy.deleteMany({
            where: { species_id: { in: speciesids } },
        }),

        db.species.deleteMany({
            where: { id: { in: speciesids } },
        }),

        // delete any orphaned genera since deleting a species may leave a genus behind
        db.$executeRaw`
                DELETE FROM taxonomy
                WHERE id IN (
                    SELECT id
                    FROM taxonomy
                    WHERE type = 'genus' AND 
                        id NOT IN (
                            SELECT taxonomy_id
                            FROM speciestaxonomy
                        )
                );
        `,
    ];
};

/**
 * Delete a host by its id (species id).
 * @param speciesid
 * @returns
 */
export const deleteHost = (speciesid: number): TaskEither<Error, DeleteResult> => {
    const deleteImages = () => TE.tryCatch(() => deleteImagesBySpeciesId(speciesid), handleError);
    const deleteHostTx = () => TE.tryCatch(() => db.$transaction(hostDeleteSteps([speciesid])), handleError);

    const toDeleteResult = (batch: Array<Prisma.BatchPayload | number>): DeleteResult => {
        return {
            type: 'host',
            name: 'host',
            // Thanks Prisma: https://github.com/prisma/prisma/discussions/7284
            count: batch.map((v) => (hasProp(v, 'count') ? (v.count as number) : v)).reduce((acc, v) => acc + v, 0),
        };
    };

    // eslint-disable-next-line prettier/prettier
    return pipe(
        deleteImages(),
        TE.chain(deleteHostTx),
        TE.map(toDeleteResult)
    );
};

export const hostsSearch = (s: string): TaskEither<Error, HostApi[]> => getHosts([{ name: { contains: s } }]);

export const hostsSearchSimple = (s: string): TaskEither<Error, SimpleSpecies[]> =>
    pipe(
        getHosts([{ name: { contains: s } }]),
        TE.map((hs) =>
            hs.map((h) => ({
                id: h.id,
                name: h.name,
                aliases: h.aliases,
                datacomplete: h.datacomplete,
                places: h.places,
                taxoncode: h.taxoncode,
            })),
        ),
    );
