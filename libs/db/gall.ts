import { alignment, cells as cs, color, location, Prisma, shape, texture, walls as ws } from '@prisma/client';
import { GallApi, GallUpsertFields } from '../apitypes';
import db from './db';
import { GallTaxon } from './dbinternaltypes';
import { speciesByName } from './species';
import { connectIfNotNull, connectWithIds } from './utils';

/**
 * Fetch all Gall ids
 * @returns a Promise that when resolved contains a string[] of all Gall ids.
 */
export const allGallIds = async (): Promise<string[]> => {
    return db.species
        .findMany({
            where: { taxoncode: { equals: GallTaxon } },
        })
        .then((sp) => sp.map((s) => s.id.toString()));
};

/**
 * A general way to fetch galls. Check this file for pre-defined helpers that are easier to use.
 * @param whereClause a where clause by which to filter galls
 */
export const getGalls = async (
    whereClause: readonly Prisma.speciesWhereInput[],
    operatorAnd = true,
    distinct: Prisma.SpeciesDistinctFieldEnum[] = [],
): Promise<GallApi[]> => {
    const w = operatorAnd
        ? { AND: [...whereClause, { taxoncode: { equals: GallTaxon } }] }
        : { AND: [{ taxoncode: { equals: GallTaxon } }, { OR: whereClause }] };

    const galls = db.species.findMany({
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

    // we want a stronger non-null contract on what we return then is modelable in the DB
    const cleaned: Promise<GallApi[]> = galls.then((gs) =>
        gs
            .flatMap((g) => {
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
                            id: h.hostspecies.id,
                            name: h.hostspecies.name,
                        };
                    }),
                };
                return newg as GallApi; // ugh, TS type-checker can not "see" that we eliminated the null.
            })
            .sort((a, b) => a.name?.localeCompare(b.name)),
    );

    return cleaned;
};

/**
 * Fetch all Galls
 * @returns a Promise that when resolved contains a GallApi[] of all Galls
 */
export const allGalls = async (): Promise<GallApi[]> => {
    return getGalls([]);
};

/**
 * Fetch all Galls of the given host
 * @param hostName the host name to filter by
 * @returns a Promise that when resolved contains a GallApi[] of all galls of the hostName
 */
export const gallsByHostName = async (hostName: string): Promise<GallApi[]> => {
    return getGalls([{ hosts: { some: { hostspecies: { name: { equals: hostName } } } } }]);
};

/**
 * Fetch all Galls of the given host
 * @param hostGenus the host genus to filter by
 * @returns a Promise that when resolved contains a GallApi[] of all galls of the hostGenus
 */
export const gallsByHostGenus = async (hostGenus: string): Promise<GallApi[]> => {
    return getGalls([{ hosts: { some: { hostspecies: { genus: { equals: hostGenus } } } } }]);
};

/**
 * Fetches the gall with the given id
 * @param id the id of the gall to fetch
 * @returns a Promise that when resolved contains the GallApi of the mathcing gall or null if a matching gall was not found
 */
export const gallById = (id: string): Promise<GallApi | null> => {
    const gall = getGalls([{ id: parseInt(id) }]).then((g) => {
        if (g.length > 0) {
            return g[0];
        } else {
            return null;
        }
    });

    return gall;
};

/**
 * Fetches all of the genera for all of the galls
 * @returns a Promise that when resolved contains a string[] of all gall genera
 */
export const allGallGenera = async (): Promise<string[]> => {
    return db.species
        .findMany({
            select: {
                genus: true,
            },
            distinct: [Prisma.SpeciesDistinctFieldEnum.genus],
            where: { taxoncode: { equals: GallTaxon } },
            orderBy: { genus: 'asc' },
        })
        .then((g) => g.map((g) => g.genus));
};

/**
 * Fetches all gall locations
 */
export const locations = async (): Promise<location[]> => {
    return db.location.findMany({
        orderBy: {
            location: 'asc',
        },
    });
};

/**
 * Fetches all gall colors
 */
export const colors = async (): Promise<color[]> => {
    return db.color.findMany({
        orderBy: {
            color: 'asc',
        },
    });
};

/**
 * Fetches all gall shapes
 */
export const shapes = async (): Promise<shape[]> => {
    return db.shape.findMany({
        orderBy: {
            shape: 'asc',
        },
    });
};

/**
 * Fetches all gall textures
 */
export const textures = async (): Promise<texture[]> => {
    return db.texture.findMany({
        orderBy: {
            texture: 'asc',
        },
    });
};

/**
 * Fetches all gall alignments
 */
export const alignments = async (): Promise<alignment[]> => {
    return db.alignment.findMany({
        orderBy: {
            alignment: 'asc',
        },
    });
};

/**
 * Fetches all gall walls
 */
export const walls = async (): Promise<ws[]> => {
    return db.walls.findMany({
        orderBy: {
            walls: 'asc',
        },
    });
};

/**
 * Fetches all gall cells
 */
export const cells = async (): Promise<cs[]> => {
    return db.cells.findMany({
        orderBy: {
            cells: 'asc',
        },
    });
};

/**
 * Insert or update a gall based on its existence in the DB.
 * @param gall the data to update or insert
 * @returns a Promise when resolved that will containe the id of the species created (a Gall is just a specialization of a species)
 */
export const upsertGall = async (gall: GallUpsertFields): Promise<number> => {
    // first create or update the species record then the gall - upsert may work but it is tricky to get right as we have
    // to separately create the gall if the species does not exist.
    const checkSpeciesExists = await speciesByName(gall.name);

    const spData = {
        family: { connect: { name: gall.family } },
        abundance: connectIfNotNull<Prisma.abundanceCreateOneWithoutSpeciesInput>('abundance', gall.abundance),
        synonyms: gall.synonyms,
        commonnames: gall.commonnames,
        hosts: {
            connect: connectWithIds('id', gall.hosts),
        },
    };

    const gallData = {
        alignment: connectIfNotNull<Prisma.alignmentCreateOneWithoutGallInput>('alignment', gall.alignment),
        cells: connectIfNotNull<Prisma.cellsCreateOneWithoutGallInput>('cells', gall.cells),
        color: connectIfNotNull<Prisma.colorCreateOneWithoutGallInput>('color', gall.color),
        detachable: gall.detachable ? 1 : 0,
        shape: connectIfNotNull<Prisma.shapeCreateOneWithoutGallInput>('shape', gall.shape),
        walls: connectIfNotNull<Prisma.wallsCreateOneWithoutGallInput>('walls', gall.walls),
        galllocation: {
            connect: connectWithIds('location', gall.locations),
        },
        galltexture: {
            connect: connectWithIds('texture', gall.textures),
        },
    };

    let theSp = null;
    if (checkSpeciesExists != null) {
        db.$transaction([
            (theSp = await db.species.create({
                data: {
                    ...spData,
                    name: gall.name,
                    genus: gall.name.split(' ')[0],
                    taxontype: { connect: { taxoncode: GallTaxon } },
                },
            })),
            db.gall.create({
                data: {
                    ...gallData,
                    species_id: theSp.id,
                    taxontype: { connect: { taxoncode: GallTaxon } },
                },
            }),
        ]);
    } else {
        theSp = await db.species.update({
            data: {
                ...spData,
                gall: {
                    update: {
                        ...gallData,
                        galllocation: {
                            // this seems stupid but I can not figure out a way to update these many-to-many
                            // like is provided with the 'set' operation for 1-to-many. :(
                            deleteMany: { location_id: { notIn: [] } },
                            connect: gallData.galllocation.connect,
                        },
                        galltexture: {
                            deleteMany: { texture_id: { notIn: [] } },
                            connect: gallData.galltexture.connect,
                        },
                    },
                },
            },
            where: { name: gall.name },
        });
    }

    return theSp.id;
};
