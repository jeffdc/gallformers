import { family, Prisma, species } from '@prisma/client';
import { pipe } from 'fp-ts/lib/function';
import * as TE from 'fp-ts/lib/TaskEither';
import { TaskEither } from 'fp-ts/lib/TaskEither';
import { DeleteResult, FamilyApi, FamilyUpsertFields, GallTaxon, HostTaxon, SpeciesApi } from '../api/apitypes';
import { handleError } from '../utils/util';
import db from './db';
import { gallDeleteSteps, getGalls } from './gall';
import { getSpecies } from './species';
import { extractId } from './utils';

export const familyById = (id: number): TaskEither<Error, family[]> => {
    const family = () =>
        db.family.findMany({
            where: { id: { equals: id } },
        });

    return TE.tryCatch(family, handleError);
};

export const speciesByFamily = (id: number): TaskEither<Error, species[]> => {
    const families = () =>
        db.species.findMany({
            where: { family_id: { equals: id } },
            orderBy: { name: 'asc' },
        });

    return TE.tryCatch(families, handleError);
};

export const allFamilies = (): TaskEither<Error, family[]> => {
    const families = () =>
        db.family.findMany({
            orderBy: { name: 'asc' },
        });

    return TE.tryCatch(families, handleError);
};

export const getGallMakerFamilies = (): TaskEither<Error, FamilyApi[]> => {
    const families = () =>
        db.family.findMany({
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

    return TE.tryCatch(families, handleError);
};

export const getHostFamilies = (): TaskEither<Error, FamilyApi[]> => {
    const families = () =>
        db.family.findMany({
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

    return TE.tryCatch(families, handleError);
};

export const allFamilyIds = (): TaskEither<Error, string[]> => {
    const families = () =>
        db.family.findMany({
            select: { id: true },
        });

    return pipe(
        TE.tryCatch(families, handleError),
        TE.map((x) => x.map(extractId).map((n) => n.toString())),
    );
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

export const deleteFamily = (id: number): TaskEither<Error, DeleteResult> => {
    const deleteTx = (speciesids: number[], gallids: number[]) =>
        TE.tryCatch(() => db.$transaction(gallDeleteSteps(speciesids, gallids).concat(familyDeleteSteps(id))), handleError);

    const galls = (speciesids: number[]) => getGalls([{ id: { in: speciesids } }]);

    const toDeleteResult = (batch: Prisma.BatchPayload[]): DeleteResult => {
        return {
            type: 'family',
            name: '',
            count: batch.reduce((acc, v) => acc + v.count, 0),
        };
    };

    // I am sure that there is a way to map the Species and Gall arrays to number arrays before the point of use
    // but I struggled figuring it out, got lost in "type soup".
    return pipe(
        TE.bindTo('speciesids')(getAllSpeciesForFamily(id)),
        TE.bind('gallids', ({ speciesids }) => galls(speciesids.map(extractId))),
        TE.map(({ speciesids, gallids }) => deleteTx(speciesids.map(extractId), gallids.map(extractId))),
        TE.flatten,
        TE.map(toDeleteResult),
    );
};

export const upsertFamily = (f: FamilyUpsertFields): TaskEither<Error, number> => {
    const upsert = () =>
        db.family.upsert({
            where: { name: f.name },
            update: {
                description: f.description,
            },
            create: {
                name: f.name,
                description: f.description,
            },
        });
    return pipe(
        TE.tryCatch(upsert, handleError),
        TE.map((sp) => sp.id),
    );
};
