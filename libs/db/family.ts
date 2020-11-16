import { family, species } from '@prisma/client';
import db from './db';

export const familyById = async (id: number): Promise<family | null> => {
    return db.family.findFirst({
        where: { id: { equals: id } },
    });
};

export const speciesByFamily = async (id: number): Promise<species[]> => {
    return db.species.findMany({
        where: { family_id: { equals: id } },
        orderBy: { name: 'asc' },
    });
};

export const allFamilies = async (): Promise<family[]> => {
    return db.family.findMany({
        orderBy: { name: 'asc' },
    });
};
