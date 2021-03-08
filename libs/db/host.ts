import { abundance, alias, aliasspecies, host, image, Prisma, source, species, speciessource, taxonomy } from '@prisma/client';
import { pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import * as TE from 'fp-ts/lib/TaskEither';
import { TaskEither } from 'fp-ts/lib/TaskEither';
import { DeleteResult, HostApi, HostSimple, HostTaxon, SpeciesUpsertFields, UpsertResult } from '../api/apitypes';
import { GENUS, SECTION } from '../api/taxonomy';
import { handleError, optionalWith } from '../utils/util';
import db from './db';
import { adaptImage } from './images';
import { adaptAbundance } from './species';

//TODO switch over to model like is beign done in gall.ts with derived type rather than explicit
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
};

// we want a stronger non-null contract on what we return then is modelable in the DB
const adaptor = (hosts: DBHost[]): HostApi[] =>
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
        };
        return newh;
    });

const simplify = (hosts: HostApi[]) =>
    hosts.map((h) => {
        return {
            name: h.name,
            id: h.id,
            aliases: h.aliases,
        };
    });

/**
 * Fetch all hosts.
 */
export const allHosts = (): TaskEither<Error, HostApi[]> => getHosts();

/**
 * Fetch all hosts into a HostSimple format.
 */
export const allHostsSimple = (): TaskEither<Error, HostSimple[]> => pipe(allHosts(), TE.map(simplify));

/**
 * Fetch all host names as a string[].
 */
export const allHostNames = (): TaskEither<Error, string[]> =>
    pipe(
        allHosts(),
        TE.map((hosts) => hosts.map((h) => h.name)),
    );

/**
 * Fetch all of the Genera and Sections for the hosts.
 */
export const allHostGenera = (): TaskEither<Error, taxonomy[]> => {
    const genera = () =>
        db.taxonomy.findMany({
            include: {
                parent: true,
            },
            where: {
                OR: [
                    {
                        AND: [
                            { type: GENUS },
                            {
                                speciestaxonomy: {
                                    every: {
                                        species: {
                                            taxoncode: HostTaxon,
                                        },
                                    },
                                },
                            },
                        ],
                    },
                    { type: SECTION },
                ],
            },
        });

    return pipe(TE.tryCatch(genera, handleError));
};

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
            },
            where: w,
            distinct: distinct,
            orderBy: { name: 'asc' },
        });

    return pipe(TE.tryCatch(hosts, handleError), TE.map(adaptor));
};

/**
 * Fetch a host by its ID.
 * @param id
 */
export const hostById = (id: number): TaskEither<Error, HostApi[]> => getHosts([{ id: id }]);

/**
 * Fetch all hosts for the given genus.
 * @param genus
 * @returns
 */
export const hostsByGenus = (genus: string): TaskEither<Error, HostApi[]> => {
    if (!genus || genus.length === 0) return TE.taskEither.of([]);

    return getHosts([{ taxonomy: { every: { taxonomy: { type: GENUS } } } }]);
};

const hostUpsertSteps = (host: SpeciesUpsertFields): Promise<number>[] => {
    // delete all aliases that are no longer present in the incoming list of aliases
    const aliasDeletes = db.$executeRaw(`
        DELETE FROM alias
        WHERE alias.id IN (
            SELECT a.id
            FROM alias AS a
                INNER JOIN
                aliasspecies AS s ON a.id = s.alias_id
                WHERE s.species_id = ${host.id} AND
                a.name NOT IN (${host.aliases.map((a) => a.name).join(',')});
    `);

    const aliasUpserts = host.aliases.map((a) =>
        db.alias
            .upsert({
                where: { id: a.id },
                update: {
                    ...a,
                },
                create: {
                    ...a,
                },
            })
            .then(() => 1),
    );

    const newAliasSpeciesMappings = db.$executeRaw(`
            INSERT INTO aliasspecies (id, alias_id, species_id)
            VALUES ${host.aliases
                .filter((a) => a.id < 0)
                .map((a) => `(NULL, ${a.id}, ${host.id})`)
                .join(',')}
    `);

    const abundanceConnect = () => {
        if (host.abundance) {
            return { connect: { abundance: host.abundance } };
        } else {
            return {};
        }
    };

    const connectOrCreateGenus = {
        connectOrCreate: {
            where: { taxonomy_id_species_id: { species_id: host.id, taxonomy_id: host.fgs.genus.id } },
            create: {
                taxonomy: {
                    connectOrCreate: {
                        where: { id: host.fgs.genus.id },
                        create: {
                            description: host.fgs.genus.description,
                            name: host.fgs.genus.name,
                            type: GENUS,
                        },
                    },
                },
            },
        },
    };

    const upsertHost = db.species
        .upsert({
            where: { id: host.id },
            update: {
                name: host.name,
                datacomplete: host.datacomplete,
                abundance: abundanceConnect(),
                taxonomy: connectOrCreateGenus,
            },
            create: {
                name: host.name,
                taxontype: { connect: { taxoncode: HostTaxon } },
                abundance: abundanceConnect(),
                taxonomy: connectOrCreateGenus,
            },
            include: { taxonomy: { include: { taxonomy: true } } },
        })
        .then((h) => {
            // Family must already exist so just need to add a mapping if it is not already present
            const genus = h.taxonomy.find((t) => t.taxonomy.type === GENUS);
            if (genus == undefined) throw new Error('Could not find genus for species');

            db.taxonomytaxonomy.upsert({
                where: { taxonomy_id_child_id: { taxonomy_id: host.fgs.family.id, child_id: genus.taxonomy_id } },
                create: { child: genus.taxonomy, taxonomy: host.fgs.family },
                update: {},
            });

            // Section must already exist so just need to add mapping if present
            return h.id;
        });

    return [aliasDeletes, ...aliasUpserts, upsertHost, newAliasSpeciesMappings];
};

/**
 * Update or insert a host.
 * @param h
 * @returns
 */
export const upsertHost = (h: SpeciesUpsertFields): TaskEither<Error, UpsertResult> => {
    const upsertHostTx = TE.tryCatch(() => db.$transaction(hostUpsertSteps(h)), handleError);

    const toUpsertResult = (batch: number[]): UpsertResult => {
        const id = batch.pop();
        return {
            type: 'host',
            name: '',
            count: batch.reduce((acc, v) => acc + v, 0),
            id: id,
        };
    };

    return pipe(upsertHostTx, TE.map(toUpsertResult));
};

/**
 * The steps required to delete a Host. This is a hack to fake CASCADE DELETE since Prisma does not support it yet.
 * See: https://github.com/prisma/prisma/issues/2057
 * @param speciesids an array of ids of the species (host) to delete
 */
const hostDeleteSteps = (speciesids: number[]): Promise<Prisma.BatchPayload>[] => {
    return [
        db.host.deleteMany({
            where: { host_species_id: { in: speciesids } },
        }),

        db.speciessource.deleteMany({
            where: { species_id: { in: speciesids } },
        }),

        db.species.deleteMany({
            where: { id: { in: speciesids } },
        }),
    ];
};

/**
 * Delete a host by its id (species id).
 * @param speciesid
 * @returns
 */
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
