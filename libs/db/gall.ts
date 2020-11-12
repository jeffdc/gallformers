import { alignment, cells as cs, color, location, PrismaClient, shape, texture, walls as ws } from '@prisma/client';

const db = new PrismaClient();

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
