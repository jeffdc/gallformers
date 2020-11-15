import { PrismaClient, species } from '@prisma/client';

const db = new PrismaClient();

export const allHosts = async (): Promise<species[]> => {
    return db.species.findMany({
        where: { taxoncode: { equals: null } },
        orderBy: { name: 'asc' },
    });
};
