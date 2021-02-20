import { species, taxonomy } from '@prisma/client';
import * as E from 'fp-ts/lib/Either';
import { identity, pipe } from 'fp-ts/lib/function';
import * as TE from 'fp-ts/lib/TaskEither';
import { TaskEither } from 'fp-ts/lib/TaskEither';
import {
    ALL_FAMILY_TYPES,
    DeleteResult,
    FAMILY,
    FamilyGallTypesTuples,
    FamilyHostTypesTuple,
    FamilyTypesTuple,
    invalidTaxonomyType,
    SpeciesApi,
    TaxonomyApi,
    TaxonomyTypeT,
    TaxonomyUpsertFields,
    FamilyGeneraSpecies,
} from '../api/apitypes';
import { handleError } from '../utils/util';
import db from './db';
import { gallDeleteSteps } from './gall';
import { getSpecies } from './species';
import { extractId } from './utils';

export const adaptTaxonomy = (t: taxonomy): TaxonomyApi => ({
    ...t,
    type: pipe(TaxonomyTypeT.decode(t.type), E.fold(invalidTaxonomyType, identity)),
    children: [],
});

export const taxonomyById = (id: number): TaskEither<Error, taxonomy[]> => {
    const tax = () =>
        db.taxonomy.findMany({
            where: { id: { equals: id } },
        });

    return TE.tryCatch(tax, handleError);
};

export const speciesByTaxonomy = (id: number): TaskEither<Error, species[]> => {
    const sps = () =>
        db.speciestaxonomy
            .findMany({
                include: { species: true },
                where: { taxonomy_id: { equals: id } },
            })
            .then((st) => st.map((s) => s.species));
    // db.species.findMany({
    //     where: { family_id: { equals: id } },
    //     orderBy: { name: 'asc' },
    // });

    return TE.tryCatch(sps, handleError);
};

export const allFamilies = (
    types: FamilyTypesTuple | FamilyGallTypesTuples | FamilyHostTypesTuple = ALL_FAMILY_TYPES,
): TaskEither<Error, TaxonomyApi[]> => {
    const families = () =>
        db.taxonomy.findMany({
            orderBy: { name: 'asc' },
            where: { description: { in: [...types] } },
        });

    return pipe(
        TE.tryCatch(families, handleError),
        TE.map((f) => f.map(adaptTaxonomy)),
    );
};

export const getFamiliesWithSpecies = (gall: boolean) => (): TaskEither<Error, FamilyGeneraSpecies[]> => {
    const fams = () => {
        const where = gall
            ? [{ type: FAMILY }, { description: { not: 'Plant' } }]
            : [{ type: FAMILY }, { description: { equals: 'Plant' } }];

        return db.taxonomy.findMany({
            include: {
                // find the genera in the family
                taxonomytaxonomy: {
                    include: {
                        child: {
                            include: {
                                // and the species in the genera
                                speciestaxonomy: {
                                    include: {
                                        species: true,
                                    },
                                },
                            },
                        },
                    },
                },
            },
            where: {
                AND: where,
            },
            orderBy: { name: 'asc' },
        });
    };

    return TE.tryCatch(fams, handleError);
};

export const allFamilyIds = (): TaskEither<Error, string[]> => {
    const families = () =>
        db.taxonomy.findMany({
            select: { id: true },
            where: { type: { equals: 'family' } },
        });

    return pipe(
        TE.tryCatch(families, handleError),
        TE.map((x) => x.map(extractId).map((n) => n.toString())),
    );
};

export const getAllSpeciesForFamily = (id: number): TaskEither<Error, SpeciesApi[]> => {
    return getSpecies([{ taxonomy: { every: { id: id } } }]);
};

export const familyDeleteSteps = (familyid: number): Promise<number>[] => {
    return [
        db.taxonomy
            .deleteMany({
                where: { id: familyid },
            })
            .then((batch) => batch.count),
    ];
};

export const deleteFamily = (id: number): TaskEither<Error, DeleteResult> => {
    const deleteTx = (speciesids: number[]) =>
        TE.tryCatch(() => db.$transaction(gallDeleteSteps(speciesids).concat(familyDeleteSteps(id))), handleError);

    const toDeleteResult = (batch: number[]): DeleteResult => {
        return {
            type: 'family',
            name: '',
            count: batch.reduce((acc, v) => acc + v, 0),
        };
    };

    return pipe(
        getAllSpeciesForFamily(id),
        TE.map((species) => species.map(extractId)),
        TE.map(deleteTx),
        TE.flatten,
        TE.map(toDeleteResult),
    );
};

export const upsertFamily = (f: TaxonomyUpsertFields): TaskEither<Error, number> => {
    const upsert = () =>
        db.taxonomy.upsert({
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
