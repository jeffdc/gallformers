import {
    alignment,
    cells as cs,
    color,
    location,
    shape,
    species,
    SpeciesDistinctFieldEnum,
    texture,
    walls as ws,
} from '@prisma/client';
import { GallApi } from '../apitypes';
import db from './db';

export const allGallIds = async (): Promise<string[]> => {
    return db.species
        .findMany({
            where: { taxoncode: { equals: 'gall' } },
        })
        .then((sp) => sp.map((s) => s.id.toString()));
};

export const allGalls = async (): Promise<species[]> => {
    return db.species.findMany({
        where: { taxoncode: { equals: 'gall' } },
        orderBy: { name: 'asc' },
    });
};

export const gallById = (id: string): Promise<GallApi> => {
    return db.gall.findFirst({
        include: {
            alignment: true,
            cells: true,
            color: true,
            walls: true,
            shape: true,
            species: {
                include: {
                    taxontype: true,
                    family: true,
                    abundance: true,
                    speciessource: {
                        include: {
                            source: true,
                        },
                    },
                    hosts: {
                        include: {
                            hostspecies: true,
                        },
                    },
                },
            },
            galllocation: {
                select: { location: true },
            },
            galltexture: {
                select: { texture: true },
            },
        },
        where: {
            species_id: { equals: parseInt(id) },
        },
    });
};

export const allGallGenera = async (): Promise<string[]> => {
    return db.species
        .findMany({
            select: {
                genus: true,
            },
            distinct: [SpeciesDistinctFieldEnum.genus],
            where: { taxoncode: { equals: 'gall' } },
            orderBy: { genus: 'asc' },
        })
        .then((g) => g.map((g) => g.genus));
};

export const locations = async (): Promise<location[]> => {
    return db.location.findMany({
        orderBy: {
            location: 'asc',
        },
    });
};

export const colors = async (): Promise<color[]> => {
    return db.color.findMany({
        orderBy: {
            color: 'asc',
        },
    });
};

export const shapes = async (): Promise<shape[]> => {
    return db.shape.findMany({
        orderBy: {
            shape: 'asc',
        },
    });
};

export const textures = async (): Promise<texture[]> => {
    return db.texture.findMany({
        orderBy: {
            texture: 'asc',
        },
    });
};

export const alignments = async (): Promise<alignment[]> => {
    return db.alignment.findMany({
        orderBy: {
            alignment: 'asc',
        },
    });
};

export const walls = async (): Promise<ws[]> => {
    return db.walls.findMany({
        orderBy: {
            walls: 'asc',
        },
    });
};

export const cells = async (): Promise<cs[]> => {
    return db.cells.findMany({
        orderBy: {
            cells: 'asc',
        },
    });
};
