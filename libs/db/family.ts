import { family, Prisma, species } from '@prisma/client';
import { FamilyApi, SpeciesApi } from '../apitypes';
import { Option, fromNullable } from 'fp-ts/lib/Option';
import * as TE from 'fp-ts/lib/TaskEither';
import db from './db';
import { GallTaxon, HostTaxon } from './dbinternaltypes';
import { gallDeleteSteps, getGalls } from './gall';
import { getSpecies } from './species';
import { TaskEither } from 'fp-ts/lib/TaskEither';
import { flow, pipe } from 'fp-ts/lib/function';
import { handleError } from '../utils/util';
import { extractId } from './utils';

export const familyById = async (id: number): Promise<Option<family>> => {
    return db.family
        .findFirst({
            where: { id: { equals: id } },
        })
        .then((f) => fromNullable(f));
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

export const getAllSpeciesForFamily = (id: number): TaskEither<Error, SpeciesApi[]> => {
    return getSpecies([{ family_id: id }]);
};

export const familyDeleteSteps = (familyid: number): Promise<Prisma.BatchPayload>[] => {
    return [
        db.family.deleteMany({
            where: { id: familyid },
        }),
    ];
};

export const deleteFamily = (id: number): TaskEither<Error, Prisma.BatchPayload[]> => {
    const deleteTx = (speciesids: number[], gallids: number[]) =>
        TE.tryCatch(() => db.$transaction(gallDeleteSteps(speciesids, gallids).concat(familyDeleteSteps(id))), handleError);

    const galls = (speciesids: number[]) => getGalls([{ id: { in: speciesids } }]);

    // I am sure that there is a way to map the Species and Gall arrays to number arrays before the point of use
    // but I struggled figuring it out, got lost in "type soup".
    const foo = pipe(
        TE.bindTo('speciesids')(getAllSpeciesForFamily(id)),
        TE.bind('gallids', ({ speciesids }) => galls(speciesids.map(extractId))),
        TE.map(({ speciesids, gallids }) => deleteTx(speciesids.map(extractId), gallids.map(extractId))),
        TE.flatten,
    );

    return foo;
};
