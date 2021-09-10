import {
    abundance,
    alias,
    aliasspecies,
    alignment,
    cells as cs,
    color,
    form,
    gallalignment,
    gallcells,
    gallcolor,
    gallform,
    galllocation,
    gallseason,
    gallshape,
    gallspecies,
    galltexture,
    gallwalls,
    host,
    image,
    location,
    Prisma,
    PrismaPromise,
    season,
    shape,
    source,
    species,
    speciessource,
    speciestaxonomy,
    taxonomy,
    texture,
    walls as ws,
} from '@prisma/client';
import * as A from 'fp-ts/lib/Array';
import { flow, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import * as TE from 'fp-ts/lib/TaskEither';
import { TaskEither } from 'fp-ts/lib/TaskEither';
import {
    DeleteResult,
    detachableFromId,
    detachableFromString,
    GallApi,
    GallIDApi,
    GallTaxon,
    GallUpsertFields,
    SimpleSpecies,
} from '../api/apitypes';
import { FGS, GENUS, SECTION } from '../api/taxonomy';
import { deleteImagesBySpeciesId } from '../images/images';
import { defaultSource } from '../pages/renderhelpers';
import { logger } from '../utils/logger';
import { ExtractTFromPromise } from '../utils/types';
import { handleError, optionalWith } from '../utils/util';
import db from './db';
import {
    adaptAlignments,
    adaptCells,
    adaptColors,
    adaptSeasons,
    adaptShapes,
    adaptWalls,
    adaptLocations,
    adaptTextures,
    adaptForm,
} from './filterfield';
import { adaptImage, adaptImageNoSource } from './images';
import {
    adaptAbundance,
    speciesCreateData,
    speciesTaxonomyAdditionalUpdateSteps,
    speciesUpdateData,
    updateAbundance,
} from './species';
import { taxonomyForSpecies } from './taxonomy';
import { connectWithIds } from './utils';

/**
 * A general way to fetch galls. Check this file for pre-defined helpers that are easier to use.
 * @param whereClause a where clause by which to filter galls
 */
export const getGalls = (
    whereClause: Prisma.gallspeciesWhereInput[] = [],
    operatorAnd = true,
    // distinct: Prisma.GallspeciesScalarFieldEnum[] = [],
): TaskEither<Error, GallApi[]> => {
    const w = operatorAnd
        ? { AND: [...whereClause, { species: { taxoncode: GallTaxon } }] }
        : { AND: [{ species: { taxoncode: GallTaxon } }, { OR: whereClause }] };
    const galls = () =>
        db.gallspecies.findMany({
            include: {
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
                        image: { include: { source: true /*{ include: { speciessource: true } }*/ } },
                        speciestaxonomy: { include: { taxonomy: true } },
                        aliasspecies: { include: { alias: true } },
                    },
                },
                gall: {
                    select: {
                        gallalignment: { include: { alignment: true } },
                        gallcells: { include: { cells: true } },
                        gallcolor: { include: { color: true } },
                        gallseason: { include: { season: true } },
                        detachable: true,
                        galllocation: { include: { location: true } },
                        galltexture: { include: { texture: true } },
                        gallshape: { include: { shape: true } },
                        gallwalls: { include: { walls: true } },
                        gallform: { include: { form: true } },
                        undescribed: true,
                    },
                },
            },
            where: w,
            orderBy: { species: { name: 'asc' } },
        });

    // type DBGall = ExtractTFromPromise<ReturnType<typeof galls>>;
    // type DBGallWithFGS = Omit<DBGall, 'species'> & DBGall[number]['species'] & { fgs: FGS[] };
    type DBGallWithFGS = gallspecies & {
        gall: {
            gallalignment: (gallalignment & {
                alignment: alignment;
            })[];
            gallcells: (gallcells & {
                cells: cs;
            })[];
            gallcolor: (gallcolor & {
                color: color;
            })[];
            gallseason: (gallseason & {
                season: season;
            })[];
            detachable: number | null;
            galllocation: (galllocation & {
                location: location;
            })[];
            galltexture: (galltexture & {
                texture: texture;
            })[];
            gallshape: (gallshape & {
                shape: shape;
            })[];
            gallwalls: (gallwalls & {
                walls: ws;
            })[];
            gallform: (gallform & {
                form: form;
            })[];
            undescribed: boolean;
        };
        species: species & {
            abundance: abundance | null;
            aliasspecies: (aliasspecies & {
                alias: alias;
            })[];
            hosts: (host & {
                hostspecies: {
                    id: number;
                    name: string;
                } | null;
            })[];
            image: (image & {
                source:
                    | (source & {
                          speciessource: speciessource[];
                      })
                    | null;
            })[];
            speciessource: (speciessource & {
                source: source;
            })[];
            speciestaxonomy: (speciestaxonomy & {
                taxonomy: taxonomy;
            })[];
            fgs: FGS;
        };
    };

    // we want a stronger no-null contract on what we return then is modelable in the DB
    const clean = (galls: readonly DBGallWithFGS[]): GallApi[] =>
        galls.flatMap((g) => {
            if (g.gall == null) {
                logger.error(
                    `Detected a species with id ${g.species.id} that is supposed to be a gall but does not have a corresponding gall!`,
                );
                return []; // will resolve to nothing since we are in a flatMap
            }
            // set the default description to make the caller's life easier
            const d = defaultSource(g.species.speciessource)?.description;

            const newg: GallApi = {
                id: g.species_id,
                name: g.species.name,
                datacomplete: g.species.datacomplete,
                speciessource: g.species.speciessource,
                taxoncode: g.species.taxoncode ? g.species.taxoncode : '',
                description: O.fromNullable(d),
                abundance: optionalWith(g.species.abundance, adaptAbundance),
                gall: {
                    ...g.gall,
                    id: g.gall_id,
                    gallalignment: adaptAlignments(g.gall.gallalignment.map((a) => a.alignment)),
                    gallcells: adaptCells(g.gall.gallcells.map((c) => c.cells)),
                    gallcolor: adaptColors(g.gall.gallcolor.map((c) => c.color)),
                    gallseason: adaptSeasons(g.gall.gallseason.map((c) => c.season)),
                    gallshape: adaptShapes(g.gall.gallshape.map((s) => s.shape)),
                    gallwalls: adaptWalls(g.gall.gallwalls.map((w) => w.walls)),
                    detachable: detachableFromId(g.gall.detachable),
                    galllocation: adaptLocations(g.gall.galllocation.map((l) => l.location)),
                    galltexture: adaptTextures(g.gall.galltexture.map((t) => t.texture)),
                    gallform: adaptForm(g.gall.gallform.map((c) => c.form)),
                    undescribed: g.gall.undescribed,
                },
                // remove the indirection of the many-to-many table for easier usage
                hosts: g.species.hosts.map((h) => {
                    return {
                        id: h.hostspecies?.id ? h.hostspecies.id : -1,
                        name: h.hostspecies?.name ? h.hostspecies.name : 'MISSING HOST',
                    };
                }),
                images: g.species.image.map(adaptImage),
                aliases: g.species.aliasspecies.map((a) => a.alias),
                fgs: g.species.fgs,
            };
            return newg;
        });

    // eslint-disable-next-line prettier/prettier
    return pipe(
        TE.tryCatch(galls, handleError),
        TE.map(
            flow(
                A.map((g) =>
                    pipe(
                        taxonomyForSpecies(g.species_id),
                        TE.map(
                            (fgs) =>
                                ({
                                    ...g,
                                    species: {
                                        ...g.species,
                                        fgs: fgs,
                                    },
                                } as DBGallWithFGS),
                        ),
                    ),
                ),
            ),
        ),
        TE.map(TE.sequenceArray),
        TE.flatten,
        TE.map(clean),
    );
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

const gallsByHostGenusForID = (whereClause: Prisma.gallspeciesWhereInput[]): TaskEither<Error, GallIDApi[]> => {
    const w = { AND: [...whereClause, { species: { taxoncode: GallTaxon } }] };
    const galls = () =>
        db.gallspecies.findMany({
            include: {
                species: {
                    include: {
                        hosts: {
                            include: {
                                hostspecies: {
                                    select: {
                                        id: true,
                                        name: true,
                                        places: { include: { place: { select: { name: true, type: true } } } },
                                    },
                                },
                            },
                        },
                        image: true,
                        speciestaxonomy: { include: { taxonomy: true } },
                    },
                },
                gall: {
                    select: {
                        gallalignment: { include: { alignment: true } },
                        gallcells: { include: { cells: true } },
                        gallcolor: { include: { color: true } },
                        gallseason: { include: { season: true } },
                        detachable: true,
                        galllocation: { include: { location: true } },
                        galltexture: { include: { texture: true } },
                        gallshape: { include: { shape: true } },
                        gallwalls: { include: { walls: true } },
                        gallform: { include: { form: true } },
                        undescribed: true,
                    },
                },
            },
            where: w,
            orderBy: { species: { name: 'asc' } },
        });

    // helper type that makes dealing wuth the next function a lot easier
    type DBGall = ExtractTFromPromise<ReturnType<typeof galls>>;

    const clean = (galls: DBGall): GallIDApi[] =>
        galls.flatMap((g) => {
            if (g.gall == null) {
                logger.error(
                    `Detected a species with id ${g.species.id} that is supposed to be a gall but does not have a corresponding gall!`,
                );
                return []; // will resolve to nothing since we are in a flatMap
            }

            const newg: GallIDApi = {
                id: g.species_id,
                name: g.species.name,
                datacomplete: g.species.datacomplete,
                alignments: g.gall.gallalignment.map((a) => a.alignment.alignment),
                cells: g.gall.gallcells.map((c) => c.cells.cells),
                colors: g.gall.gallcolor.map((c) => c.color.color),
                seasons: g.gall.gallseason.map((c) => c.season.season),
                shapes: g.gall.gallshape.map((s) => s.shape.shape),
                walls: g.gall.gallwalls.map((w) => w.walls.walls),
                detachable: detachableFromId(g.gall.detachable),
                locations: g.gall.galllocation.map((l) => l.location.location),
                textures: g.gall.galltexture.map((t) => t.texture.texture),
                forms: g.gall.gallform.map((c) => c.form.form),
                undescribed: g.gall.undescribed,
                // remove the indirection of the many-to-many table for easier usage
                places: g.species.hosts.flatMap((h) => {
                    if (h.hostspecies == null) {
                        return [];
                    }
                    return h.hostspecies.places
                        .filter((p) => p.place.type == 'state' || p.place.type == 'province')
                        .map((p) => p.place.name);
                }),
                images: g.species.image.map(adaptImageNoSource),
            };
            return newg;
        });

    // eslint-disable-next-line prettier/prettier
    return pipe(
        TE.tryCatch(galls, handleError),
        TE.map(clean),
    );
};

/**
 * Fetch all Galls of the given host
 * @param hostName the host name to filter by
 */
export const gallsByHostName = (hostName: string): TaskEither<Error, GallIDApi[]> => {
    return gallsByHostGenusForID([{ species: { hosts: { some: { hostspecies: { name: { equals: hostName } } } } } }]);
};

/**
 * Fetch all Galls of the given host genus or section. This is for the ID screen so we will minimize the data we fetch.
 * @param hostGenus the host genus or section to filter by
 */
export const gallsByHostGenus = (hostGenus: string): TaskEither<Error, GallIDApi[]> => {
    return gallsByHostGenusForID([
        {
            species: {
                hosts: {
                    some: {
                        hostspecies: {
                            speciestaxonomy: {
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

export const gallsByHostSection = (hostSection: string): TaskEither<Error, GallIDApi[]> => {
    return gallsByHostGenusForID([
        {
            species: {
                hosts: {
                    some: {
                        hostspecies: {
                            speciestaxonomy: {
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
 * Gets all galls that have the same binomial name as the passed in name. This wokrs beacuse we are using a naming
 * convention for different galls created by the same species.
 * @param gall
 * @returns
 */
export const getRelatedGalls = (gall: GallApi): TaskEither<Error, SimpleSpecies[]> => {
    const nameParts = gall.name.split(' ');
    if (nameParts.length < 2) return TE.of([]);

    const get = () =>
        db.species.findMany({
            select: {
                id: true,
                name: true,
                taxoncode: true,
            },
            where: {
                name: {
                    startsWith: `${nameParts[0]} ${nameParts[1]}`,
                },
            },
        });

    return pipe(
        TE.tryCatch(get, handleError),
        TE.map((galls) => galls.filter((g) => g.id !== gall.id).map((g) => ({ ...g } as SimpleSpecies))),
    );
};

/**
 * Fetches the gall with the given id
 * @param id the id of the gall to fetch
 */
export const gallById = (id: number): TaskEither<Error, GallApi[]> => getGalls([{ species: { id: id } }]);

/**
 * Fetches the gall with the given id, returning it wrapped in an Option.
 * @param id
 */
export const gallByIdAsO = (id: number): TaskEither<Error, O.Option<GallApi>> =>
    pipe(
        id,
        gallById,
        TE.map((g) => O.fromNullable(g[0])),
    );

/**
 * Fetch a gall by its name.
 * @param name
 */
export const gallByName = (name: string): TaskEither<Error, GallApi[]> => getGalls([{ species: { name: name } }]);

/**
 * Fetches all of the genera for all of the galls
 */
export const allGallGenera = (): TaskEither<Error, string[]> => {
    const genera = () =>
        db.taxonomy.findMany({
            distinct: [Prisma.AliasScalarFieldEnum.type],
            where: { AND: [{ type: GENUS }, { speciestaxonomy: { every: { species: { taxoncode: GallTaxon } } } }] },
        });

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

export const testTx = (): Promise<[species[]]> => {
    return db.$transaction([db.species.findMany({ where: { name: { contains: 'alba' } } })]);
};

const gallCreateSteps = (gall: GallUpsertFields): PrismaPromise<unknown>[] => {
    return [
        db.species.create({
            data: {
                ...speciesCreateData(gall),
                taxontype: { connect: { taxoncode: GallTaxon } },
                hosts: {
                    create: connectWithIds('hostspecies', gall.hosts),
                },
                gallspecies: {
                    create: {
                        gall: {
                            create: {
                                undescribed: gall.undescribed,
                                gallalignment: { create: gall.alignments.map((id) => ({ alignment_id: id })) },
                                gallcells: { create: gall.cells.map((id) => ({ cells_id: id })) },
                                gallcolor: { create: gall.colors.map((id) => ({ color_id: id })) },
                                gallseason: { create: gall.seasons.map((id) => ({ season_id: id })) },
                                detachable: detachableFromString(gall.detachable).id,
                                gallshape: { create: gall.shapes.map((id) => ({ shape_id: id })) },
                                gallwalls: { create: gall.walls.map((id) => ({ walls_id: id })) },
                                taxontype: { connect: { taxoncode: GallTaxon } },
                                galllocation: { create: gall.locations.map((id) => ({ location_id: id })) },
                                galltexture: { create: gall.textures.map((id) => ({ texture_id: id })) },
                                gallform: { create: gall.forms.map((id) => ({ form_id: id })) },
                            },
                        },
                    },
                },
            },
        }),
    ];
};

const gallUpdateSteps = (gall: GallUpsertFields): PrismaPromise<unknown>[] => {
    return [
        db.species.update({
            where: { id: gall.id },
            data: {
                ...speciesUpdateData(gall),
                gallspecies: {
                    update: {
                        where: { species_id_gall_id: { gall_id: gall.gallid, species_id: gall.id } },
                        data: {
                            gall: {
                                update: {
                                    undescribed: gall.undescribed,
                                    detachable: detachableFromString(gall.detachable).id,
                                    gallalignment: {
                                        deleteMany: { alignment_id: { notIn: [] } },
                                        create: gall.alignments.map((a) => ({ alignment_id: a })),
                                    },
                                    gallcells: {
                                        deleteMany: { cells_id: { notIn: [] } },
                                        create: gall.cells.map((c) => ({ cells_id: c })),
                                    },
                                    gallcolor: {
                                        deleteMany: { color_id: { notIn: [] } },
                                        create: gall.colors.map((c) => ({ color_id: c })),
                                    },
                                    gallseason: {
                                        deleteMany: { season_id: { notIn: [] } },
                                        create: gall.seasons.map((c) => ({ season_id: c })),
                                    },
                                    gallshape: {
                                        deleteMany: { shape_id: { notIn: [] } },
                                        create: gall.shapes.map((s) => ({ shape_id: s })),
                                    },
                                    gallwalls: {
                                        deleteMany: { walls_id: { notIn: [] } },
                                        create: gall.walls.map((w) => ({ walls_id: w })),
                                    },
                                    galllocation: {
                                        deleteMany: { location_id: { notIn: [] } },
                                        create: gall.locations.map((l) => ({ location_id: l })),
                                    },
                                    galltexture: {
                                        deleteMany: { texture_id: { notIn: [] } },
                                        create: gall.textures.map((t) => ({ texture_id: t })),
                                    },
                                    gallform: {
                                        deleteMany: { form_id: { notIn: [] } },
                                        create: gall.forms.map((c) => ({ form_id: c })),
                                    },
                                },
                            },
                        },
                    },
                },
                hosts: {
                    deleteMany: { id: { notIn: [] } },
                    create: connectWithIds('hostspecies', gall.hosts),
                },
            },
        }),
        updateAbundance(gall.id, gall.abundance),
        ...speciesTaxonomyAdditionalUpdateSteps(gall),
    ];
};

/**
 * Insert or update a gall based on its existence in the DB.
 * @param gall the data to update or insert
 * @returns a Promise when resolved that will containe the id of the species created (a Gall is just a specialization of a species)
 */
export const upsertGall = (gall: GallUpsertFields): TaskEither<Error, GallApi> => {
    const updateGallTx = TE.tryCatch(() => db.$transaction(gallUpdateSteps(gall)), handleError);
    const createGallTx = TE.tryCatch(() => db.$transaction(gallCreateSteps(gall)), handleError);

    const getGall = () => {
        return gallByName(gall.name);
    };

    // eslint-disable-next-line prettier/prettier
    return pipe(
        gall.id < 0 ? createGallTx : updateGallTx,
        TE.chain(getGall),
        TE.fold(
            (e) => TE.left(e),
            (s) => (s.length <= 0 ? TE.left(new Error('Failed to get upserted data.')) : TE.right(s[0])),
        ),
    );
};

export const deleteGall = (speciesid: number): TaskEither<Error, DeleteResult> => {
    const deleteImages = () => TE.tryCatch(() => deleteImagesBySpeciesId(speciesid), handleError);

    // Prisma can not do cascade deletes. See: https://github.com/prisma/prisma/issues/2057
    const gallDelete = () => TE.tryCatch(() => db.$executeRaw(`DELETE FROM species WHERE id = ${speciesid}`), handleError);

    const toDeleteResult = (count: number): DeleteResult => {
        return {
            type: 'gall',
            name: speciesid.toString(),
            count: count,
        };
    };

    // eslint-disable-next-line prettier/prettier
    return pipe(
        deleteImages(),
        TE.chain(gallDelete),
        TE.map(toDeleteResult),
    );
};
