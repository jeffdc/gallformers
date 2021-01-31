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
    GallApi,
    GallLocation,
    GallTaxon,
    GallTexture,
    GallUpsertFields,
    ShapeApi,
    WallsApi,
} from '../api/apitypes';
import { deleteImagesBySpeciesId } from '../images/images';
import { defaultSource } from '../pages/renderhelpers';
import { logger } from '../utils/logger';
import { ExtractTFromPromise } from '../utils/types';
import { handleError, optionalWith } from '../utils/util';
import db from './db';
import { adaptAbundance, speciesByName } from './species';
import { connectIfNotNull, connectWithIds, extractId } from './utils';

/**
 * A general way to fetch galls. Check this file for pre-defined helpers that are easier to use.
 * @param whereClause a where clause by which to filter galls
 */
export const getGalls = (
    whereClause: Prisma.speciesWhereInput[] = [],
    operatorAnd = true,
    distinct: Prisma.SpeciesScalarFieldEnum[] = ['id'],
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

    // we want a stronger no-null contract on what we return then is modelable in the DB
    const clean = (galls: DBGall): GallApi[] =>
        galls.flatMap((g) => {
            if (g.gall == null) {
                logger.error(
                    `Detected a species with id ${g.id} that is supposed to be a gall but does not have a cooresponding gall!`,
                );
                return []; // will resolve to nothing since we are in a flatMap
            }
            // set the default description to make the caller's life easier
            const d = defaultSource(g.speciessource)?.description;

            const newg: GallApi = {
                ...g,
                taxoncode: g.taxoncode ? g.taxoncode : '',
                description: O.fromNullable(d),
                synonyms: O.fromNullable(g.synonyms),
                commonnames: O.fromNullable(g.commonnames),
                abundance: optionalWith(g.abundance, adaptAbundance),
                gall: {
                    ...g.gall,
                    alignment: optionalWith(g.gall.alignment, adaptAlignment),
                    cells: optionalWith(g.gall.cells, adaptCells),
                    color: optionalWith(g.gall.color, adaptColor),
                    shape: optionalWith(g.gall.shape, adaptShape),
                    walls: optionalWith(g.gall.walls, adaptWalls),
                    detachable: O.fromNullable(g.gall.detachable),
                    galllocation: adaptLocations(g.gall.galllocation.map((l) => l.location)),
                    galltexture: adaptTextures(g.gall.galltexture.map((t) => t.texture)),
                },
                // remove the indirection of the many-to-many table for easier usage
                hosts: g.hosts.map((h) => {
                    // due to prisma problems we had to make these hostspecies relationships optional, however
                    // if we are here then there must be a record in the host table so it can not be null :(
                    if (!h.hostspecies?.id || !h.hostspecies?.name) throw new Error('Invalid state.');
                    return {
                        id: h.hostspecies.id,
                        name: h.hostspecies.name,
                    };
                }),
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
            distinct: [Prisma.SpeciesScalarFieldEnum.genus],
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

const adaptColor = (c: color): ColorApi => c;

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

    return pipe(
        TE.tryCatch(colors, handleError),
        TE.map((c) => c.map(adaptColor)),
    );
};

const adaptShape = (s: shape): ShapeApi => ({
    ...s,
    description: O.fromNullable(s.description),
});

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

    return pipe(
        TE.tryCatch(shapes, handleError),
        TE.map((s) => s.map(adaptShape)),
    );
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

const adaptAlignment = (a: alignment): AlignmentApi => ({
    ...a,
    description: O.fromNullable(a.description),
});

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

    return pipe(
        TE.tryCatch(alignments, handleError),
        TE.map((a) => a.map(adaptAlignment)),
    );
};

const adaptWalls = (w: ws): WallsApi => ({
    ...w,
    description: O.fromNullable(w.description),
});

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

    return pipe(
        TE.tryCatch(walls, handleError),
        TE.map((w) => w.map(adaptWalls)),
    );
};

const adaptCells = (a: cs): CellsApi => ({
    ...a,
    description: O.fromNullable(a.description),
});

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

    return pipe(
        TE.tryCatch(cells, handleError),
        TE.map((c) => c.map(adaptCells)),
    );
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

    const gallData = {
        alignment: connectIfNotNull<Prisma.alignmentCreateOneWithoutGallInput, string>('alignment', gall.alignment),
        cells: connectIfNotNull<Prisma.cellsCreateOneWithoutGallInput, string>('cells', gall.cells),
        color: connectIfNotNull<Prisma.colorCreateOneWithoutGallInput, string>('color', gall.color),
        detachable: gall.detachable ? 1 : 0,
        shape: connectIfNotNull<Prisma.shapeCreateOneWithoutGallInput, string>('shape', gall.shape),
        walls: connectIfNotNull<Prisma.wallsCreateOneWithoutGallInput, string>('walls', gall.walls),
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
