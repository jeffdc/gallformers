import { PrismaClient, species } from '@prisma/client';

const db = new PrismaClient();

export const allHosts = async (): Promise<species[]> => {
    return db.species.findMany({
        where: { taxoncode: { equals: null } },
        orderBy: { name: 'asc' },
    });
};

export const upsertHost = async (h): Promise<void> => {
    await db.species.upsert({
        where: { name: h.name },
        update: {
            family: { connect: { name: h.family } },
            abundance: { connect: { abundance: h.abundance } },
            synonyms: h.synonyms,
            commonnames: h.commonnames,
            description: h.description,
        },
        create: {
            name: h.name,
            genus: h.name.split(' ')[0],
            family: { connect: { name: h.family } },
            abundance: { connect: { abundance: h.abundance } },
            synonyms: h.synonyms,
            commonnames: h.commonnames,
            description: h.description,
        },
    });
};
