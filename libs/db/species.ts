import { abundance, PrismaClient, species } from '@prisma/client';

const db = new PrismaClient();

export const abundances = async (): Promise<abundance[]> => {
    return db.abundance.findMany({
        orderBy: {
            abundance: 'asc',
        },
    });
};

export const allSpecies = async (): Promise<species[]> => {
    return db.species.findMany({
        orderBy: { name: 'asc' },
    });
};
