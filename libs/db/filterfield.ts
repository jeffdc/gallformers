import { alignment, cells as cs, color, form, location, Prisma, season, shape, texture, walls as ws } from '@prisma/client';
import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import * as TE from 'fp-ts/lib/TaskEither';
import { TaskEither } from 'fp-ts/lib/TaskEither';
import {
    DeleteResult,
    FilterField,
    FilterFieldType,
    FilterFieldWithType,
    FILTER_FIELD_ALIGNMENTS,
    FILTER_FIELD_CELLS,
    FILTER_FIELD_COLORS,
    FILTER_FIELD_FORMS,
    FILTER_FIELD_LOCATIONS,
    FILTER_FIELD_SEASONS,
    FILTER_FIELD_SHAPES,
    FILTER_FIELD_TEXTURES,
    FILTER_FIELD_WALLS,
} from '../api/apitypes';
import { handleError } from '../utils/util';
import db from './db';

export const adaptLocations = (ls: location[]): FilterField[] => {
    return ls.map((l) => ({
        id: l.id,
        field: l.location,
        description: O.fromNullable(l.description),
    }));
};

/**
 * Fetches all gall locations
 */
export const getLocations = (): TaskEither<Error, FilterField[]> => {
    const locations = () =>
        db.location.findMany({
            orderBy: {
                location: 'asc',
            },
        });

    return pipe(TE.tryCatch(locations, handleError), TE.map(adaptLocations));
};

export const adaptColors = (colors: color[]): FilterField[] =>
    colors.map((c) => ({
        id: c.id,
        field: c.color,
        description: O.none,
    }));

/**
 * Fetches all gall colors
 */
export const getColors = (): TaskEither<Error, FilterField[]> => {
    const colors = () =>
        db.color.findMany({
            orderBy: {
                color: 'asc',
            },
        });

    return pipe(TE.tryCatch(colors, handleError), TE.map(adaptColors));
};

export const adaptSeasons = (seasons: season[]): FilterField[] =>
    seasons.map((c) => ({
        id: c.id,
        field: c.season,
        description: O.none,
    }));

/**
 * Fetches all gall seasons
 */
export const getSeasons = (): TaskEither<Error, FilterField[]> => {
    const seasons = () => db.season.findMany({});

    return pipe(TE.tryCatch(seasons, handleError), TE.map(adaptSeasons));
};

export const adaptShapes = (shapes: shape[]): FilterField[] =>
    shapes.map((s) => ({
        id: s.id,
        field: s.shape,
        description: O.fromNullable(s.description),
    }));

/**
 * Fetches all gall shapes
 */
export const getShapes = (): TaskEither<Error, FilterField[]> => {
    const shapes = () =>
        db.shape.findMany({
            orderBy: {
                shape: 'asc',
            },
        });

    return pipe(TE.tryCatch(shapes, handleError), TE.map(adaptShapes));
};

export const adaptTextures = (ts: texture[]): FilterField[] => {
    return ts.map((t) => ({
        id: t.id,
        field: t.texture,
        description: O.fromNullable(t.description),
    }));
};

/**
 * Fetches all gall textures
 */
export const getTextures = (): TaskEither<Error, FilterField[]> => {
    const textures = () =>
        db.texture.findMany({
            orderBy: {
                texture: 'asc',
            },
        });

    return pipe(TE.tryCatch(textures, handleError), TE.map(adaptTextures));
};

export const adaptAlignments = (as: alignment[]): FilterField[] =>
    as.map((a) => ({
        id: a.id,
        field: a.alignment,
        description: O.fromNullable(a.description),
    }));

/**
 * Fetches all gall alignments
 */
export const getAlignments = (): TaskEither<Error, FilterField[]> => {
    const alignments = () =>
        db.alignment.findMany({
            orderBy: {
                alignment: 'asc',
            },
        });

    return pipe(TE.tryCatch(alignments, handleError), TE.map(adaptAlignments));
};

export const adaptWalls = (walls: ws[]): FilterField[] =>
    walls.map((w) => ({
        id: w.id,
        field: w.walls,
        description: O.fromNullable(w.description),
    }));

/**
 * Fetches all gall walls
 */
export const getWalls = (): TaskEither<Error, FilterField[]> => {
    const walls = () =>
        db.walls.findMany({
            orderBy: {
                walls: 'asc',
            },
        });

    return pipe(TE.tryCatch(walls, handleError), TE.map(adaptWalls));
};

export const adaptCells = (cells: cs[]): FilterField[] =>
    cells.map((c) => ({
        id: c.id,
        field: c.cells,
        description: O.fromNullable(c.description),
    }));

/**
 * Fetches all gall cells
 */
export const getCells = (): TaskEither<Error, FilterField[]> => {
    const cells = () =>
        db.cells.findMany({
            orderBy: {
                cells: 'asc',
            },
        });

    return pipe(TE.tryCatch(cells, handleError), TE.map(adaptCells));
};

export const adaptForm = (form: form[]): FilterField[] =>
    form.map((c) => ({
        id: c.id,
        field: c.form,
        description: O.fromNullable(c.description),
    }));

/**
 * Fetches all gall forms
 */
export const getForms = (): TaskEither<Error, FilterField[]> => {
    const form = () =>
        db.form.findMany({
            orderBy: {
                form: 'asc',
            },
        });

    return pipe(TE.tryCatch(form, handleError), TE.map(adaptForm));
};

export const deleteFilterField = (fieldType: FilterFieldType, id: string): TaskEither<Error, DeleteResult> => {
    const numId = parseInt(id);
    const deleteConfig = (field: string) => ({
        where: { id: numId },
        select: { [field]: true },
    });

    const results = () => {
        switch (fieldType) {
            case FILTER_FIELD_ALIGNMENTS:
                return db.alignment.delete(deleteConfig('alignment'));
            case FILTER_FIELD_CELLS:
                return db.cells.delete(deleteConfig('cells'));
            case FILTER_FIELD_COLORS:
                return db.color.delete(deleteConfig('color'));
            case FILTER_FIELD_FORMS:
                return db.form.delete(deleteConfig('form'));
            case FILTER_FIELD_LOCATIONS:
                return db.location.delete(deleteConfig('location'));
            case FILTER_FIELD_SEASONS:
                return db.season.delete(deleteConfig('season'));
            case FILTER_FIELD_SHAPES:
                return db.shape.delete(deleteConfig('shape'));
            case FILTER_FIELD_TEXTURES:
                return db.texture.delete(deleteConfig('texture'));
            case FILTER_FIELD_WALLS:
                return db.walls.delete(deleteConfig('walls'));
            default:
                return Promise.reject('Unknown type passed to deleteFilterField');
        }
    };

    const toDeleteResult = (): DeleteResult => {
        return {
            type: fieldType,
            name: id.toString(),
            count: 1,
        };
    };
    // eslint-disable-next-line prettier/prettier
    return pipe(
        // @ts-expect-error TODO fix this...
        TE.tryCatch(results, handleError),
        TE.map(toDeleteResult),
    );
};

export const upsertFilterField = (field: FilterFieldWithType): TaskEither<Error, FilterField> => {
    // I tried to make a function that could return the "upsert config" built based on a passed in value depending on
    // the type of the Filter Field but could not figure out the magic incantation of type voodoo to make it work. One
    // of the real downsides of Prisma. So hold your hat as we go on the copy and paste ride.
    const upsert = (): Promise<FilterField> => {
        switch (field.fieldType) {
            case FILTER_FIELD_ALIGNMENTS:
                return db.alignment
                    .upsert({
                        where: { id: field.id },
                        update: {
                            alignment: field.field,
                            description: O.getOrElse(constant(''))(field.description),
                        },
                        create: {
                            alignment: field.field,
                            description: O.getOrElse(constant(''))(field.description),
                        },
                    })
                    .then((v) => ({
                        ...v,
                        field: v.alignment,
                        description: O.fromNullable(v.description),
                    }));
            case FILTER_FIELD_CELLS:
                return db.cells
                    .upsert({
                        where: { id: field.id },
                        update: {
                            cells: field.field,
                            description: O.getOrElse(constant(''))(field.description),
                        },
                        create: {
                            cells: field.field,
                            description: O.getOrElse(constant(''))(field.description),
                        },
                    })
                    .then((v) => ({
                        ...v,
                        field: v.cells,
                        description: O.fromNullable(v.description),
                    }));
            case FILTER_FIELD_COLORS:
                return db.color
                    .upsert({
                        where: { id: field.id },
                        update: {
                            color: field.field,
                        },
                        create: {
                            color: field.field,
                        },
                    })
                    .then((v) => ({
                        ...v,
                        field: v.color,
                        description: O.none,
                    }));

            case FILTER_FIELD_FORMS:
                return db.form
                    .upsert({
                        where: { id: field.id },
                        update: {
                            form: field.field,
                            description: O.getOrElse(constant(''))(field.description),
                        },
                        create: {
                            form: field.field,
                            description: O.getOrElse(constant(''))(field.description),
                        },
                    })
                    .then((v) => ({
                        ...v,
                        field: v.form,
                        description: O.fromNullable(v.description),
                    }));

            case FILTER_FIELD_LOCATIONS:
                return db.location
                    .upsert({
                        where: { id: field.id },
                        update: {
                            location: field.field,
                            description: O.getOrElse(constant(''))(field.description),
                        },
                        create: {
                            location: field.field,
                            description: O.getOrElse(constant(''))(field.description),
                        },
                    })
                    .then((v) => ({
                        ...v,
                        field: v.location,
                        description: O.fromNullable(v.description),
                    }));

            case FILTER_FIELD_SEASONS:
                return db.season
                    .upsert({
                        where: { id: field.id },
                        update: {
                            season: field.field,
                        },
                        create: {
                            season: field.field,
                        },
                    })
                    .then((v) => ({
                        ...v,
                        field: v.season,
                        description: O.none,
                    }));

            case FILTER_FIELD_SHAPES:
                return db.shape
                    .upsert({
                        where: { id: field.id },
                        update: {
                            shape: field.field,
                            description: O.getOrElse(constant(''))(field.description),
                        },
                        create: {
                            shape: field.field,
                            description: O.getOrElse(constant(''))(field.description),
                        },
                    })
                    .then((v) => ({
                        ...v,
                        field: v.shape,
                        description: O.fromNullable(v.description),
                    }));

            case FILTER_FIELD_TEXTURES:
                return db.texture
                    .upsert({
                        where: { id: field.id },
                        update: {
                            texture: field.field,
                            description: O.getOrElse(constant(''))(field.description),
                        },
                        create: {
                            texture: field.field,
                            description: O.getOrElse(constant(''))(field.description),
                        },
                    })
                    .then((v) => ({
                        ...v,
                        field: v.texture,
                        description: O.fromNullable(v.description),
                    }));

            case FILTER_FIELD_WALLS:
                return db.walls
                    .upsert({
                        where: { id: field.id },
                        update: {
                            walls: field.field,
                            description: O.getOrElse(constant(''))(field.description),
                        },
                        create: {
                            walls: field.field,
                            description: O.getOrElse(constant(''))(field.description),
                        },
                    })
                    .then((v) => ({
                        ...v,
                        field: v.walls,
                        description: O.fromNullable(v.description),
                    }));

            default:
                return Promise.reject('Unknown type passed to upsertFilterField');
        }
    };

    // eslint-disable-next-line prettier/prettier
    return pipe(
        TE.tryCatch(upsert, handleError),
    );
};

type Wheres = Prisma.alignmentWhereInput &
    Prisma.cellsWhereInput &
    Prisma.colorWhereInput &
    Prisma.formWhereInput &
    Prisma.locationWhereInput &
    Prisma.seasonWhereInput &
    Prisma.shapeWhereInput &
    Prisma.textureWhereInput &
    Prisma.wallsWhereInput;

const getFilterFields = (where: Wheres, fieldType: FilterFieldType): TaskEither<Error, FilterField[]> => {
    switch (fieldType) {
        case 'alignments':
            return pipe(
                TE.tryCatch(() => db.alignment.findMany({ where: where }), handleError),
                TE.map(adaptAlignments),
            );
        case 'cells':
            return pipe(
                TE.tryCatch(() => db.cells.findMany({ where: where }), handleError),
                TE.map(adaptCells),
            );
        case 'colors':
            return pipe(
                TE.tryCatch(() => db.color.findMany({ where: where }), handleError),
                TE.map(adaptColors),
            );
        case 'forms':
            return pipe(
                TE.tryCatch(() => db.form.findMany({ where: where }), handleError),
                TE.map(adaptForm),
            );
        case 'locations':
            return pipe(
                TE.tryCatch(() => db.location.findMany({ where: where }), handleError),
                TE.map(adaptLocations),
            );
        case 'seasons':
            return pipe(
                TE.tryCatch(() => db.season.findMany({ where: where }), handleError),
                TE.map(adaptSeasons),
            );
        case 'shapes':
            return pipe(
                TE.tryCatch(() => db.shape.findMany({ where: where }), handleError),
                TE.map(adaptShapes),
            );
        case 'textures':
            return pipe(
                TE.tryCatch(() => db.texture.findMany({ where: where }), handleError),
                TE.map(adaptTextures),
            );
        case 'walls':
            return pipe(
                TE.tryCatch(() => db.walls.findMany({ where: where }), handleError),
                TE.map(adaptWalls),
            );
        default:
            return Promise.reject;
    }
};

export const getFilterFieldByIdAndType = (id: number, fieldType: FilterFieldType): TaskEither<Error, FilterField[]> => {
    return getFilterFields({ id: id }, fieldType);
};

export const getFilterFieldByNameAndType = (name: string, fieldType: FilterFieldType): TaskEither<Error, FilterField[]> => {
    switch (fieldType) {
        case 'alignments':
            return getFilterFields({ alignment: name }, fieldType);
        case 'cells':
            return getFilterFields({ cells: name }, fieldType);
        case 'colors':
            return getFilterFields({ color: name }, fieldType);
        case 'forms':
            return getFilterFields({ form: name }, fieldType);
        case 'locations':
            return getFilterFields({ location: name }, fieldType);
        case 'seasons':
            return getFilterFields({ season: name }, fieldType);
        case 'shapes':
            return getFilterFields({ shape: name }, fieldType);
        case 'textures':
            return getFilterFields({ texture: name }, fieldType);
        case 'walls':
            return getFilterFields({ walls: name }, fieldType);
        default:
            return Promise.reject;
    }
};

export const getFilterFieldsByType = (fieldType: FilterFieldType): TaskEither<Error, FilterField[]> => {
    return getFilterFields({}, fieldType);
};
