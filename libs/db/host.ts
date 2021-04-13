import {
    abundance,
    alias,
    aliasspecies,
    host,
    image,
    Prisma,
    PrismaPromise,
    source,
    species,
    speciessource,
} from '@prisma/client';
import { flow, pipe } from 'fp-ts/lib/function';
import * as A from 'fp-ts/lib/Array';
import * as O from 'fp-ts/lib/Option';
import * as TE from 'fp-ts/lib/TaskEither';
import { TaskEither } from 'fp-ts/lib/TaskEither';
import { DeleteResult, HostApi, HostSimple, HostTaxon, SpeciesApi, SpeciesUpsertFields } from '../api/apitypes';
import { FGS, GENUS } from '../api/taxonomy';
import { deleteImagesBySpeciesId } from '../images/images';
import { handleError, optionalWith } from '../utils/util';
import db from './db';
import { adaptImage } from './images';
import { adaptAbundance, connectOrCreateGenus, updateAbundance } from './species';
import { taxonomyForSpecies } from './taxonomy';
import { connectIfNotNull } from './utils';

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
const hostUpdateSteps = (host: SpeciesUpsertFields): PrismaPromise<unknown>[] => {
    return [
        db.species.update({
            where: { id: host.id },
            data: {
                // more Prisma stupidity: disconnecting a record that is not connected throws. :(
                // so instead of this:
                // abundance: host.abundance
                //     ? {
                //           connect: { abundance: host.abundance },
                //       }
                //     : {
                //           disconnect: true,
                //       },
                //   we instead have to have a totally separate step in the transaction to update abundance 😠
                datacomplete: host.datacomplete,
                name: host.name,
                aliasspecies: {
                    // typical hack, delete them all and then add
                    deleteMany: { species_id: host.id },
                    create: host.aliases.map((a) => ({
                        alias: { create: { description: a.description, name: a.name, type: a.type } },
                    })),
                },
            },
        }),
        // the abundance update referenced above:
        updateAbundance(host.id, host.abundance),
        // the genus could have been changed and might be new
        // TODO I believe that this can lead to orphaned genus records in the taxonomy table.
        // Also could lead to a genus being assigned to >1 Family
        db.speciestaxonomy.deleteMany({ where: { AND: [{ species_id: host.id }, { taxonomy: { type: GENUS } }] } }),
        db.speciestaxonomy.create({
            data: {
                species: { connect: { id: host.id } },
                taxonomy: connectOrCreateGenus(host),
            },
        }),
    ];
};

const hostCreate = (host: SpeciesUpsertFields) => {
    return db.species.create({
        data: {
            name: host.name,
            taxontype: { connect: { taxoncode: HostTaxon } },
            abundance: connectIfNotNull<Prisma.abundanceCreateNestedOneWithoutSpeciesInput, string>('abundance', host.abundance),
            speciestaxonomy: {
                create: [
                    // family must already exist
                    { taxonomy: { connect: { id: host.fgs.family.id } } },
                    // genus could be new
                    {
                        taxonomy: connectOrCreateGenus(host),
                    },
                ],
            },
            aliasspecies: {
                create: host.aliases.map((a) => ({
                    alias: { create: { description: a.description, name: a.name, type: a.type } },
                })),
            },
        },
    });
};

/**
 * Update or insert a host.
 * @param h
 * @returns
 */
export const upsertHost = (h: SpeciesUpsertFields): TaskEither<Error, SpeciesApi> => {
    const updateHostTx = TE.tryCatch(() => db.$transaction(hostUpdateSteps(h)), handleError);
    const createHostTx = pipe(
        TE.tryCatch(() => hostCreate(h), handleError),
        TE.map((s) => [s] as unknown[]),
    );

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
const hostDeleteSteps = (speciesids: number[]): PrismaPromise<Prisma.BatchPayload>[] => {
    return [
        db.host.deleteMany({
            where: { host_species_id: { in: speciesids } },
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

    const toDeleteResult = (batch: Prisma.BatchPayload[]): DeleteResult => {
        return {
            type: 'host',
            name: 'host',
            count: batch.reduce((acc, v) => acc + v.count, 0),
        };
    };

    // eslint-disable-next-line prettier/prettier
    return pipe(
        deleteImages(),
        TE.chain(deleteHostTx),
        TE.map(toDeleteResult)
    );
};
