import { species, SpeciesDistinctFieldEnum } from '@prisma/client';
import db from './db';
import { mightBeNull } from './utils';

export const allHosts = async (): Promise<species[]> => {
    return db.species.findMany({
        where: { taxoncode: { equals: null } },
        orderBy: { name: 'asc' },
    });
};

export type HostSimple = {
    id: number;
    name: string;
    commonnames: string;
    synonyms: string;
};

export const allHostsSimple = async (): Promise<HostSimple[]> => {
    return allHosts().then((hosts) =>
        hosts
            .map((h) => {
                return {
                    name: h.name,
                    id: h.id,
                    commonnames: mightBeNull(h.commonnames),
                    synonyms: mightBeNull(h.synonyms),
                };
            })
            .sort((a, b) => a.name?.localeCompare(b.name)),
    );
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
