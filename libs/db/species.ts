import { abundance, PrismaClient } from '@prisma/client';

const db = new PrismaClient();

export const abundances = async (): Promise<abundance[]> => {
    return db.abundance.findMany({
        orderBy: {
            abundance: 'asc',
        },
    });
};
