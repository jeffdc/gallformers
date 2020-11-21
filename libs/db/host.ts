import { species, SpeciesDistinctFieldEnum } from '@prisma/client';
import db from './db';

export const allHosts = async (): Promise<species[]> => {
    return db.species.findMany({
        where: { taxoncode: { equals: null } },
        orderBy: { name: 'asc' },
    });
};

export const allHostNames = async (): Promise<string[]> => {
    return allHosts().then((hosts) => hosts.map((h) => h.name));
};

export const allHostGenera = async (): Promise<string[]> => {
    return db.species
        .findMany({
            select: {
                genus: true,
            },
            distinct: [SpeciesDistinctFieldEnum.genus],
            where: { taxoncode: { equals: null } },
            orderBy: { genus: 'asc' },
        })
        .then((hosts) => hosts.map((host) => host.genus));
};
