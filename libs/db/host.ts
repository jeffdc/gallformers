import { species, SpeciesDistinctFieldEnum } from '@prisma/client';
import { HostApi, HostSimple } from '../apitypes';
import db from './db';
import { HostTaxon } from './dbinternaltypes';
import { mightBeNull } from './utils';

export const allHosts = async (): Promise<species[]> => {
    return db.species.findMany({
        where: { taxoncode: { equals: HostTaxon } },
        orderBy: { name: 'asc' },
    });
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

export const allHostIds = async (): Promise<string[]> => {
    return db.species
        .findMany({
            select: { id: true },
            where: { taxoncode: { equals: 'plant' } },
        })
        .then((hosts) => hosts.map((host) => host.id.toString()));
};

export const hostById = async (id: string): Promise<HostApi | null> => {
    return db.species.findFirst({
        include: {
            abundance: true,
            family: true,
            host_galls: {
                include: {
                    gallspecies: {
                        select: { id: true, name: true },
                    },
                },
            },
            speciessource: {
                include: { source: true },
            },
        },
        where: {
            id: { equals: parseInt(id) },
        },
    });
};
