import { abundance, species } from '@prisma/client';
import db from './db';

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
