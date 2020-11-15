import { PrismaClient, source } from '@prisma/client';

const db = new PrismaClient();

export const sourceById = async (id: number): Promise<source | null> => {
    return db.source.findFirst({
        where: { id: { equals: id } },
    });
};

// export const speciesByFamily = async (id: number): Promise<species[]> => {
//     return db.species.findMany({
//         where: { family_id: { equals: id } },
//         orderBy: { name: 'asc' },
//     });
// };

export const allSources = async (): Promise<source[]> => {
    return db.source.findMany({
        orderBy: { title: 'asc' },
    });
};
