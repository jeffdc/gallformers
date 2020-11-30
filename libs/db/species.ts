import { abundance, Prisma, species } from '@prisma/client';
import { SpeciesApi } from '../apitypes';
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

export const speciesByName = async (name: string): Promise<species | null> => {
    return db.species.findFirst({
        where: {
            name: name,
        },
    });
};

export const getSpecies = async (
    whereClause: Prisma.speciesWhereInput[],
    operatorAnd = true,
    distinct: Prisma.SpeciesDistinctFieldEnum[] = [],
): Promise<SpeciesApi[]> => {
    const w: Prisma.speciesWhereInput = operatorAnd ? { AND: whereClause } : { OR: whereClause };

    const species = db.species.findMany({
        include: {
            abundance: true,
            family: true,
            speciessource: { include: { source: true } },
        },
        where: w,
        distinct: distinct,
        orderBy: { name: 'asc' },
    });

    // we want a stronger non-null contract on what we return then is modelable in the DB
    const cleaned: Promise<SpeciesApi[]> = species.then((sps) =>
        sps.flatMap((s) => {
            // set the default description to make the caller's life easier
            const d = s.speciessource.find((s) => s.useasdefault === 1)?.description;
            const newg = {
                ...s,
                description: d ? d : '',
            };
            return newg;
        }),
    );

    return cleaned;
};
