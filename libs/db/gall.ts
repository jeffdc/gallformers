import { alignment, cells as cs, color, location, Prisma, shape, texture, walls as ws } from '@prisma/client';
import { pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import * as TE from 'fp-ts/lib/TaskEither';
import { TaskEither } from 'fp-ts/lib/TaskEither';
import { DeleteResult, GallApi, GallTaxon, GallUpsertFields } from '../api/apitypes';
import { ExtractTFromPromise, handleError } from '../utils/util';
import db from './db';
import { speciesByName } from './species';
import { connectIfNotNull, connectWithIds, extractId } from './utils';

/**
 * A general way to fetch galls. Check this file for pre-defined helpers that are easier to use.
 * @param whereClause a where clause by which to filter galls
 */
export const getGalls = (
    whereClause: readonly Prisma.speciesWhereInput[] = [],
    operatorAnd = true,
    distinct: Prisma.SpeciesDistinctFieldEnum[] = ['id'],
): TaskEither<Error, GallApi[]> => {
    const w = operatorAnd
        ? { AND: [...whereClause, { taxoncode: { equals: GallTaxon } }] }
        : { AND: [{ taxoncode: { equals: GallTaxon } }, { OR: whereClause }] };

    const galls = () =>
        db.species.findMany({
            include: {
                abundance: true,
                family: true,
                gall: {
                    select: {
                        alignment: true,
                        cells: true,
                        color: true,
                        detachable: true,
                        galllocation: { include: { location: true } },
                        galltexture: { include: { texture: true } },
                        shape: true,
                        walls: true,
                    },
                },
                hosts: {
                    include: {
                        hostspecies: { select: { id: true, name: true } },
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

    type DBGall = ExtractTFromPromise<ReturnType<typeof galls>>;

    // we want a stronger non-null contract on what we return then is modelable in the DB
    const clean = (galls: DBGall): GallApi[] =>
        galls.flatMap((g) => {
            if (g.gall == null) {
                console.error(
                    `Detected a species with id ${g.id} that is supposed to be a gall but does not have a cooresponding gall!`,
                );
                return []; // will resolve to nothing since we are in a flatMap
            }
            // set the default description to make the caller's life easier
            const d = g.speciessource.find((s) => s.useasdefault === 1)?.description;
            const newg = {
                ...g,
                description: d ? d : '',
                // remove the indirection of the many-to-many table for easier usage
                hosts: g.hosts.map((h) => {
                    return {
                        // due to prisma problems we had to make these hostspecies relationships optional, however
                        // if we are here then there must be a record in the host table so it can not be null :(
                        id: h.hostspecies?.id,
                        name: h.hostspecies?.name,
                    };
                }),
            };
            return newg as GallApi; // ugh, TS type-checker can not "see" that we eliminated the null.
        });

    return pipe(TE.tryCatch(galls, handleError), TE.map(clean));
};

/**
 * Fetch all Galls
 */
export const allGalls = (): TaskEither<Error, GallApi[]> => {
    return getGalls();
};

/**
 * Fetch all Gall ids
 */
export const allGallIds = (): TaskEither<Error, string[]> => {
    const galls = () =>
        db.species.findMany({
            select: { id: true },
            where: { taxoncode: { equals: GallTaxon } },
        });

    return pipe(
        TE.tryCatch(galls, handleError),
        TE.map((galls) => galls.map((g) => g.id.toString())),
    );
};

/**
 * Fetch all Galls of the given host
 * @param hostName the host name to filter by
 */
export const gallsByHostName = (hostName: string): TaskEither<Error, GallApi[]> => {
    return getGalls([{ hosts: { some: { hostspecies: { name: { equals: hostName } } } } }]);
};

/**
 * Fetch all Galls of the given host
 * @param hostGenus the host genus to filter by
 */
export const gallsByHostGenus = (hostGenus: string): TaskEither<Error, GallApi[]> => {
    return getGalls([{ hosts: { some: { hostspecies: { genus: { equals: hostGenus } } } } }]);
};

/**
 * Fetches the gall with the given id
 * @param id the id of the gall to fetch
 */
export const gallById = (id: number): TaskEither<Error, GallApi[]> => {
    return getGalls([{ id: id }]);
};

/**
 * Fetches all of the genera for all of the galls
 */
export const allGallGenera = (): TaskEither<Error, string[]> => {
    const genera = () =>
        db.species.findMany({
            select: {
                genus: true,
            },
            distinct: [Prisma.SpeciesDistinctFieldEnum.genus],
            where: { taxoncode: { equals: GallTaxon } },
            orderBy: { genus: 'asc' },
        });

    return pipe(
        TE.tryCatch(genera, handleError),
        TE.map((gs) => gs.map((g) => g.genus)),
    );
};

export const getGallIdsFromSpeciesIds = (speciesids: number[]): TaskEither<Error, number[]> => {
    const galls = () =>
        db.gall.findMany({
            select: { id: true },
            where: { species_id: { in: speciesids } },
        });

    return pipe(
        TE.tryCatch(galls, handleError),
        TE.map((gs) => gs.map((g) => g.id)),
    );
};

export const getGallIdFromSpeciesId = (speciesid: number): TaskEither<Error, O.Option<number>> => {
    const gall = () =>
        db.gall.findFirst({
            select: { id: true },
            where: { species_id: { equals: speciesid } },
        });

    return pipe(
        TE.tryCatch(gall, handleError),
        TE.map((g) => O.fromNullable(g?.id)),
    );
};

/**
 * Fetches all gall locations
 */
export const locations = (): TaskEither<Error, location[]> => {
    const locations = () =>
        db.location.findMany({
            orderBy: {
                location: 'asc',
            },
        });

    return TE.tryCatch(locations, handleError);
};

/**
 * Fetches all gall colors
 */
export const colors = (): TaskEither<Error, color[]> => {
    const colors = () =>
        db.color.findMany({
            orderBy: {
                color: 'asc',
            },
        });

    return TE.tryCatch(colors, handleError);
};

/**
 * Fetches all gall shapes
 */
export const shapes = (): TaskEither<Error, shape[]> => {
    const shapes = () =>
        db.shape.findMany({
            orderBy: {
                shape: 'asc',
            },
        });

    return TE.tryCatch(shapes, handleError);
};

/**
 * Fetches all gall textures
 */
export const textures = (): TaskEither<Error, texture[]> => {
    const textures = () =>
        db.texture.findMany({
            orderBy: {
                texture: 'asc',
            },
        });

    return TE.tryCatch(textures, handleError);
};

/**
 * Fetches all gall alignments
 */
export const alignments = (): TaskEither<Error, alignment[]> => {
    const alignments = () =>
        db.alignment.findMany({
            orderBy: {
                alignment: 'asc',
            },
        });

    return TE.tryCatch(alignments, handleError);
};

/**
 * Fetches all gall walls
 */
export const walls = (): TaskEither<Error, ws[]> => {
    const walls = () =>
        db.walls.findMany({
            orderBy: {
                walls: 'asc',
            },
        });

    return TE.tryCatch(walls, handleError);
};

/**
 * Fetches all gall cells
 */
export const cells = (): TaskEither<Error, cs[]> => {
    const cells = () =>
        db.cells.findMany({
            orderBy: {
                cells: 'asc',
            },
        });

    return TE.tryCatch(cells, handleError);
};

/**
 * Insert or update a gall based on its existence in the DB.
 * @param gall the data to update or insert
 * @returns a Promise when resolved that will containe the id of the species created (a Gall is just a specialization of a species)
 */
export const upsertGall = (gall: GallUpsertFields): TaskEither<Error, number> => {
    const spData = {
        family: { connect: { name: gall.family } },
        abundance: connectIfNotNull<Prisma.abundanceCreateOneWithoutSpeciesInput>('abundance', gall.abundance),
        synonyms: gall.synonyms,
        commonnames: gall.commonnames,
    };

    const gallData = {
        alignment: connectIfNotNull<Prisma.alignmentCreateOneWithoutGallInput>('alignment', gall.alignment),
        cells: connectIfNotNull<Prisma.cellsCreateOneWithoutGallInput>('cells', gall.cells),
        color: connectIfNotNull<Prisma.colorCreateOneWithoutGallInput>('color', gall.color),
        detachable: gall.detachable ? 1 : 0,
        shape: connectIfNotNull<Prisma.shapeCreateOneWithoutGallInput>('shape', gall.shape),
        walls: connectIfNotNull<Prisma.wallsCreateOneWithoutGallInput>('walls', gall.walls),
    };

    const create = () =>
        db.species.create({
            data: {
                ...spData,
                name: gall.name,
                genus: gall.name.split(' ')[0],
                taxontype: { connect: { taxoncode: GallTaxon } },
                hosts: {
                    create: connectWithIds('hostspecies', gall.hosts),
                },
                gall: {
                    create: {
                        ...gallData,
                        taxontype: { connect: { taxoncode: GallTaxon } },
                        galllocation: { create: connectWithIds('location', gall.locations) },
                        galltexture: { create: connectWithIds('texture', gall.textures) },
                    },
                },
            },
        });

    const update = () =>
        db.species.update({
            data: {
                ...spData,
                gall: {
                    update: {
                        ...gallData,
                        galllocation: {
                            // this seems stupid but I can not figure out a way to update these many-to-many
                            // like is provided with the 'set' operation for 1-to-many. :(
                            deleteMany: { location_id: { notIn: [] } },
                            create: connectWithIds('location', gall.locations),
                        },
                        galltexture: {
                            deleteMany: { texture_id: { notIn: [] } },
                            create: connectWithIds('texture', gall.textures),
                        },
                    },
                },
                hosts: {
                    deleteMany: { id: { notIn: [] } },
                    create: connectWithIds('hostspecies', gall.hosts),
                },
            },
            where: { name: gall.name },
        });

    //TODO how to get rid of the if..else?
    if (speciesByName(gall.name)) {
        return pipe(TE.tryCatch(update, handleError), TE.map(extractId));
    } else {
        return pipe(TE.tryCatch(create, handleError), TE.map(extractId));
    }
};

/**
 * The steps required to delete a Gall. This is a hack to fake CASCADE DELETE since Prisma does not support it yet.
 * See: https://github.com/prisma/prisma/issues/2057
 * @param speciesids an array of ids of the species (gall) to delete
 * @param gallids an array of ids of the gall to delete
 */
export const gallDeleteSteps = (speciesids: number[], gallids: number[]): Promise<Prisma.BatchPayload>[] => {
    return [
        db.galllocation.deleteMany({
            where: { gall_id: { in: gallids } },
        }),

        db.galltexture.deleteMany({
            where: { gall_id: { in: gallids } },
        }),

        db.gall.deleteMany({
            where: { id: { in: gallids } },
        }),

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

export const deleteGall = (speciesid: number): TaskEither<Error, DeleteResult> => {
    const deleteGallTx = (gallid: number) =>
        TE.tryCatch(() => db.$transaction(gallDeleteSteps([speciesid], [gallid])), handleError);

    const notAGallErr = () => TE.left(new Error('You can not delete a species that is not a Gall with this API.'));

    const toDeleteResult = (batch: Prisma.BatchPayload[]): DeleteResult => {
        return {
            type: 'gall',
            name: '',
            count: batch.reduce((acc, v) => acc + v.count, 0),
        };
    };

    // eslint-disable-next-line prettier/prettier
    return pipe(
        getGallIdFromSpeciesId(speciesid),
        TE.map(O.fold(notAGallErr, deleteGallTx)),
        TE.flatten,
        TE.map(toDeleteResult)
    );
};
