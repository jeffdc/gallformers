import { alignment, cells as cs, color, location, Prisma, shape, texture, walls as ws } from '@prisma/client';
import { pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import * as TE from 'fp-ts/lib/TaskEither';
import { TaskEither } from 'fp-ts/lib/TaskEither';
import {
    AlignmentApi,
    CellsApi,
    ColorApi,
    DeleteResult,
    detachableFromId,
    detachableFromString,
    GallApi,
    GallLocation,
    GallTaxon,
    GallTexture,
    GallUpsertFields,
    ShapeApi,
    WallsApi,
} from '../api/apitypes';
import { GENUS, SECTION } from '../api/taxonomy';
import { deleteImagesBySpeciesId } from '../images/images';
import { defaultSource } from '../pages/renderhelpers';
import { logger } from '../utils/logger';
import { ExtractTFromPromise } from '../utils/types';
import { handleError, optionalWith } from '../utils/util';
import db from './db';
import { adaptImage } from './images';
import { adaptAbundance, speciesByName } from './species';
import { connectIfNotNull, connectWithIds, extractId } from './utils';

/**
 * A general way to fetch galls. Check this file for pre-defined helpers that are easier to use.
 * @param whereClause a where clause by which to filter galls
 */
export const getGalls = (
    whereClause: Prisma.gallspeciesWhereInput[] = [],
    operatorAnd = true,
    distinct: Prisma.GallspeciesScalarFieldEnum[] = ['id'],
): TaskEither<Error, GallApi[]> => {
    const w = operatorAnd
        ? { AND: [...whereClause, { species: { taxoncode: GallTaxon } }] }
        : { AND: [{ species: { taxoncode: GallTaxon } }, { OR: whereClause }] };
    const galls = () =>
        db.gallspecies.findMany({
            include: {
                // family: true,
                species: {
                    include: {
                        abundance: true,
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
                        image: { include: { source: { include: { speciessource: true } } } },
                        taxonomy: { include: { taxonomy: true } },
                        aliasspecies: { include: { alias: true } },
                    },
                },
                gall: {
                    select: {
                        gallalignment: { include: { alignment: true } },
                        gallcells: { include: { cells: true } },
                        gallcolor: { include: { color: true } },
                        detachable: true,
                        galllocation: { include: { location: true } },
                        galltexture: { include: { texture: true } },
                        gallshape: { include: { shape: true } },
                        gallwalls: { include: { walls: true } },
                    },
                },
            },
            where: w,
            distinct: distinct,
            // orderBy: { name: 'asc' },
        });

    type DBGall = ExtractTFromPromise<ReturnType<typeof galls>>;

    // we want a stronger no-null contract on what we return then is modelable in the DB
    const clean = (galls: DBGall): GallApi[] =>
        galls.flatMap((g) => {
            if (g.gall == null) {
                logger.error(
                    `Detected a species with id ${g.id} that is supposed to be a gall but does not have a corresponding gall!`,
                );
                return []; // will resolve to nothing since we are in a flatMap
            }
            // set the default description to make the caller's life easier
            const d = defaultSource(g.species.speciessource)?.description;

            const newg: GallApi = {
                ...g.species,
                taxoncode: g.species.taxoncode ? g.species.taxoncode : '',
                description: O.fromNullable(d),
                abundance: optionalWith(g.species.abundance, adaptAbundance),
                gall: {
                    ...g.gall,
                    gallalignment: adaptAlignments(g.gall.gallalignment.map((a) => a.alignment)),
                    gallcells: adaptCells(g.gall.gallcells.map((c) => c.cells)),
                    gallcolor: adaptColors(g.gall.gallcolor.map((c) => c.color)),
                    gallshape: adaptShapes(g.gall.gallshape.map((s) => s.shape)),
                    gallwalls: adaptWalls(g.gall.gallwalls.map((w) => w.walls)),
                    detachable: detachableFromId(g.gall.detachable),
                    galllocation: adaptLocations(g.gall.galllocation.map((l) => l.location)),
                    galltexture: adaptTextures(g.gall.galltexture.map((t) => t.texture)),
                },
                // remove the indirection of the many-to-many table for easier usage
                hosts: g.species.hosts.map((h) => {
                    // due to prisma problems we had to make these hostspecies relationships optional, however
                    // if we are here then there must be a record in the host table so it can not be null :(
                    if (!h.hostspecies?.id || !h.hostspecies?.name) throw new Error('Invalid state.');
                    return {
                        id: h.hostspecies.id,
                        name: h.hostspecies.name,
                    };
                }),
                images: g.species.image.map(adaptImage),
                aliases: g.species.aliasspecies.map((a) => a.alias),
            };
            return newg;
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
    return getGalls([{ species: { hosts: { some: { hostspecies: { name: { equals: hostName } } } } } }]);
};

/**
 * Fetch all Galls of the given host genus or section
 * @param hostGenus the host genus or section to filter by
 */
export const gallsByHostGenus = (hostGenus: string): TaskEither<Error, GallApi[]> => {
    return getGalls([
        {
            species: {
                hosts: {
                    some: {
                        hostspecies: {
                            taxonomy: {
                                some: {
                                    taxonomy: {
                                        AND: [{ type: GENUS }, { name: hostGenus }],
                                    },
                                },
                            },
                        },
                    },
                },
            },
        },
    ]);
};

export const gallsByHostSection = (hostSection: string): TaskEither<Error, GallApi[]> => {
    return getGalls([
        {
            species: {
                hosts: {
                    some: {
                        hostspecies: {
                            taxonomy: {
                                some: {
                                    taxonomy: {
                                        AND: [{ type: SECTION }, { name: hostSection }],
                                    },
                                },
                            },
                        },
                    },
                },
            },
        },
    ]);
};

/**
 * Fetches the gall with the given id
 * @param id the id of the gall to fetch
 */
export const gallById = (id: number): TaskEither<Error, GallApi[]> => {
    return getGalls([{ species: { id: id } }]);
};

/**
 * Fetches all of the genera for all of the galls
 */
export const allGallGenera = (): TaskEither<Error, string[]> => {
    const genera = () =>
        db.taxonomy.findMany({
            distinct: [Prisma.AliasScalarFieldEnum.type],
            where: { AND: [{ type: GENUS }, { speciestaxonomy: { every: { species: { taxoncode: GallTaxon } } } }] },
        });
    // db.species.findMany({
    //     select: {
    //         genus: true,
    //     },
    //     distinct: [Prisma.SpeciesScalarFieldEnum.genus],
    //     where: { taxoncode: { equals: GallTaxon } },
    //     orderBy: { genus: 'asc' },
    // });

    return pipe(
        TE.tryCatch(genera, handleError),
        TE.map((gs) => gs.map((g) => g.name)),
    );
};

export const getGallIdsFromSpeciesIds = (speciesids: number[]): TaskEither<Error, number[]> => {
    const galls = () =>
        db.gallspecies.findMany({
            select: { gall_id: true },
            where: { species_id: { in: speciesids } },
        });

    return pipe(
        TE.tryCatch(galls, handleError),
        TE.map((gs) => gs.map((g) => g.gall_id)),
    );
};

export const getGallIdFromSpeciesId = (speciesid: number): TaskEither<Error, O.Option<number>> => {
    const gall = () =>
        db.gallspecies.findFirst({
            select: { gall_id: true },
            where: { species_id: { equals: speciesid } },
        });

    return pipe(
        TE.tryCatch(gall, handleError),
        TE.map((g) => O.fromNullable(g?.gall_id)),
    );
};

const adaptLocations = (ls: location[]): GallLocation[] => {
    return ls.map((l) => ({
        id: l.id,
        loc: l.location,
        description: O.fromNullable(l.description),
    }));
};

/**
 * Fetches all gall locations
 */
export const locations = (): TaskEither<Error, GallLocation[]> => {
    const locations = () =>
        db.location.findMany({
            orderBy: {
                location: 'asc',
            },
        });

    return pipe(TE.tryCatch(locations, handleError), TE.map(adaptLocations));
};

const adaptColors = (colors: color[]): ColorApi[] => colors.map((c) => c);

/**
 * Fetches all gall colors
 */
export const colors = (): TaskEither<Error, ColorApi[]> => {
    const colors = () =>
        db.color.findMany({
            orderBy: {
                color: 'asc',
            },
        });

    return pipe(TE.tryCatch(colors, handleError), TE.map(adaptColors));
};

const adaptShapes = (shapes: shape[]): ShapeApi[] =>
    shapes.map((s) => ({
        ...s,
        description: O.fromNullable(s.description),
    }));

/**
 * Fetches all gall shapes
 */
export const shapes = (): TaskEither<Error, ShapeApi[]> => {
    const shapes = () =>
        db.shape.findMany({
            orderBy: {
                shape: 'asc',
            },
        });

    return pipe(TE.tryCatch(shapes, handleError), TE.map(adaptShapes));
};

const adaptTextures = (ts: texture[]): GallTexture[] => {
    return ts.map((t) => ({
        id: t.id,
        tex: t.texture,
        description: O.fromNullable(t.description),
    }));
};

/**
 * Fetches all gall textures
 */
export const textures = (): TaskEither<Error, GallTexture[]> => {
    const textures = () =>
        db.texture.findMany({
            orderBy: {
                texture: 'asc',
            },
        });

    return pipe(TE.tryCatch(textures, handleError), TE.map(adaptTextures));
};

const adaptAlignments = (as: alignment[]): AlignmentApi[] =>
    as.map((a) => ({
        ...a,
        description: O.fromNullable(a.description),
    }));

/**
 * Fetches all gall alignments
 */
export const alignments = (): TaskEither<Error, AlignmentApi[]> => {
    const alignments = () =>
        db.alignment.findMany({
            orderBy: {
                alignment: 'asc',
            },
        });

    return pipe(TE.tryCatch(alignments, handleError), TE.map(adaptAlignments));
};

const adaptWalls = (walls: ws[]): WallsApi[] =>
    walls.map((w) => ({
        ...w,
        description: O.fromNullable(w.description),
    }));

/**
 * Fetches all gall walls
 */
export const walls = (): TaskEither<Error, WallsApi[]> => {
    const walls = () =>
        db.walls.findMany({
            orderBy: {
                walls: 'asc',
            },
        });

    return pipe(TE.tryCatch(walls, handleError), TE.map(adaptWalls));
};

const adaptCells = (cells: cs[]): CellsApi[] =>
    cells.map((c) => ({
        ...c,
        description: O.fromNullable(c.description),
    }));

/**
 * Fetches all gall cells
 */
export const cells = (): TaskEither<Error, CellsApi[]> => {
    const cells = () =>
        db.cells.findMany({
            orderBy: {
                cells: 'asc',
            },
        });

    return pipe(TE.tryCatch(cells, handleError), TE.map(adaptCells));
};

/**
 * Insert or update a gall based on its existence in the DB.
 * @param gall the data to update or insert
 * @returns a Promise when resolved that will containe the id of the species created (a Gall is just a specialization of a species)
 */
export const upsertGall = (gall: GallUpsertFields): TaskEither<Error, number> => {
    const spData = {
        family: { connect: { name: gall.family } },
        abundance: connectIfNotNull<Prisma.abundanceCreateOneWithoutSpeciesInput, string>('abundance', gall.abundance),
        synonyms: gall.synonyms,
        commonnames: gall.commonnames,
    };

    const create = () =>
        db.species.create({
            data: {
                ...spData,
                name: gall.name,
                // genus: gall.name.split(' ')[0],
                taxontype: { connect: { taxoncode: GallTaxon } },
                hosts: {
                    create: connectWithIds('hostspecies', gall.hosts),
                },
                gall: {
                    create: {
                        gallalignment: { create: connectWithIds('alignment', gall.alignments) },
                        gallcells: { create: connectWithIds('cells', gall.cells) },
                        gallcolor: { create: connectWithIds('color', gall.colors) },
                        detachable: detachableFromString(gall.detachable).id,
                        gallshape: { create: connectWithIds('shape', gall.shapes) },
                        gallwalls: { create: connectWithIds('walls', gall.walls) },
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
                        // this seems stupid but I can not figure out a way to update these many-to-many
                        // like is provided with the 'set' operation for 1-to-many. :(
                        gallalignment: {
                            deleteMany: { alignment_id: { notIn: [] } },
                            create: connectWithIds('alignment', gall.alignments),
                        },
                        gallcells: {
                            deleteMany: { cells_id: { notIn: [] } },
                            create: connectWithIds('cells', gall.cells),
                        },
                        gallcolor: {
                            deleteMany: { color_id: { notIn: [] } },
                            create: connectWithIds('color', gall.colors),
                        },
                        detachable: detachableFromString(gall.detachable).id,
                        gallshape: {
                            deleteMany: { shape_id: { notIn: [] } },
                            create: connectWithIds('shape', gall.shapes),
                        },
                        gallwalls: {
                            deleteMany: { walls_id: { notIn: [] } },
                            create: connectWithIds('walls', gall.walls),
                        },
                        galllocation: {
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

    return pipe(
        speciesByName(gall.name),
        // eslint-disable-next-line prettier/prettier
        TE.map(
            O.fold(
                () => TE.tryCatch(create, handleError),
                () => TE.tryCatch(update, handleError),
            ),
        ),
        TE.flatten,
        TE.map(extractId),
    );
};

/**
 * The steps required to delete a Gall. This is a hack to fake CASCADE DELETE since Prisma does not support it yet.
 * See: https://github.com/prisma/prisma/issues/2057
 *
 * @param speciesids an array of ids of the species (gall) to delete
 */
export const gallDeleteSteps = (speciesids: number[]): Promise<number>[] => {
    return [db.$executeRaw(`DELETE FROM species WHERE id IN (${speciesids})`)];
};

export const deleteGall = (speciesid: number): TaskEither<Error, DeleteResult> => {
    const deleteImages = () => TE.tryCatch(() => deleteImagesBySpeciesId(speciesid), handleError);

    const deleteGallTx = () => TE.tryCatch(() => db.$transaction(gallDeleteSteps([speciesid])), handleError);

    const toDeleteResult = (batch: number[]): DeleteResult => {
        return {
            type: 'gall',
            name: '',
            count: batch.reduce((acc, v) => acc + v, 0),
        };
    };

    // eslint-disable-next-line prettier/prettier
    return pipe(
        deleteImages(),
        TE.chain(deleteGallTx),
        TE.map(toDeleteResult),
    );
};
