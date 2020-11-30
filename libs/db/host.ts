import { Prisma, species } from '@prisma/client';
import { HostApi, HostSimple, SpeciesUpsertFields } from '../apitypes';
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
            distinct: [Prisma.SpeciesDistinctFieldEnum.genus],
            where: { taxoncode: { equals: HostTaxon } },
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

export const upsertHost = async (h: SpeciesUpsertFields): Promise<number> => {
    const abundanceConnect = () => {
        if (h.abundance) {
            return { connect: { abundance: h.abundance } };
        } else {
            return {};
        }
    };

    const sp = db.species.upsert({
        where: { name: h.name },
        update: {
            family: { connect: { name: h.family } },
            abundance: { connect: { abundance: h.abundance } },
            synonyms: h.synonyms,
            commonnames: h.commonnames,
        },
        create: {
            name: h.name,
            genus: h.name.split(' ')[0],
            taxontype: { connect: { taxoncode: HostTaxon } },
            family: { connect: { name: h.family } },
            abundance: abundanceConnect(),
            synonyms: h.synonyms,
            commonnames: h.commonnames,
        },
    });

    return sp.then((s) => s.id);
};
