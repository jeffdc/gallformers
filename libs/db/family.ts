import { family, species } from '@prisma/client';
import { FamilyApi } from '../apitypes';
import db from './db';
import { GallTaxon, HostTaxon } from './dbinternaltypes';

export const familyById = async (id: number): Promise<family | null> => {
    return db.family.findFirst({
        where: { id: { equals: id } },
    });
};

export const speciesByFamily = async (id: number): Promise<species[]> => {
    return db.species.findMany({
        where: { family_id: { equals: id } },
        orderBy: { name: 'asc' },
    });
};

export const allFamilies = async (): Promise<family[]> => {
    return db.family.findMany({
        orderBy: { name: 'asc' },
    });
};

export const getGallMakerFamilies = async (): Promise<FamilyApi[]> => {
    return db.family.findMany({
        include: {
            species: {
                select: {
                    id: true,
                    name: true,
                    gall: { include: { species: { select: { id: true, name: true } } } },
                },
                where: { taxoncode: GallTaxon },
                orderBy: { name: 'asc' },
            },
        },
        where: { description: { not: 'Plant' } },
        orderBy: { name: 'asc' },
    });
};

export const getHostFamilies = async (): Promise<FamilyApi[]> => {
    return db.family.findMany({
        include: {
            species: {
                select: {
                    id: true,
                    name: true,
                    gall: { include: { species: { select: { id: true, name: true } } } },
                },
                where: { taxoncode: HostTaxon },
                orderBy: { name: 'asc' },
            },
        },
        where: { description: { equals: 'Plant' } },
        orderBy: { name: 'asc' },
    });
};

export const allFamilyIds = async (): Promise<string[]> => {
    return db.family
        .findMany({
            select: { id: true },
        })
        .then((fs) => fs.map((f) => f.id.toString()));
};
