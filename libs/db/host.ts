import { species } from '@prisma/client';
import db from './db';

export const allHosts = async (): Promise<species[]> => {
    return db.species.findMany({
        where: { taxoncode: { equals: null } },
        orderBy: { name: 'asc' },
    });
};
