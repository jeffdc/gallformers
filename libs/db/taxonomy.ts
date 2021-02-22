import { Prisma, speciestaxonomy, taxonomy, taxonomytaxonomy } from '@prisma/client';
import * as E from 'fp-ts/lib/Either';
import { identity, pipe } from 'fp-ts/lib/function';
import { never } from 'fp-ts/lib/Task';
import * as TE from 'fp-ts/lib/TaskEither';
import { TaskEither } from 'fp-ts/lib/TaskEither';
import {
    ALL_FAMILY_TYPES,
    DeleteResult,
    FAMILY,
    FamilyGallTypesTuples,
    FamilyGeneraSpecies,
    FamilyHostTypesTuple,
    FamilyTypesTuple,
    GENUS,
    invalidTaxonomyType,
    SpeciesApi,
    TaxonomyApi,
    TaxonomyTree,
    TaxonomyTypeT,
    TaxonomyUpsertFields,
    TaxTreeForSpecies,
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

export const taxonomyForId = (id: number): TaskEither<Error, TaxonomyTree[]> => {
    const sps = () =>
        db.taxonomy.findMany({
            include: {
                parent: true,
                speciestaxonomy: {
                    include: {
                        species: true,
                    },
                },
                taxonomy: {
                    include: {
                        speciestaxonomy: {
                            include: {
                                species: true,
                            },
                        },
                        taxonomy: true,
                        taxonomyalias: true,
                        taxonomytaxonomy: true,
                    },
                },
                taxonomyalias: true,
            },
            where: {
                id: id,
            },
        });

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

export const taxonomyForSpecies = (id: number): TaskEither<Error, TaxTreeForSpecies> => {
    const tree = (): Prisma.Prisma__speciestaxonomyClient<
        | (speciestaxonomy & {
              taxonomy: taxonomy & {
                  parent: taxonomy | null;
                  taxonomy: taxonomy[];
                  taxonomytaxonomy: (taxonomytaxonomy & {
                      taxonomy: taxonomy;
                      child: taxonomy;
                  })[];
              };
          })
        | never
    > => {
        const r = db.speciestaxonomy.findFirst({
            include: {
                taxonomy: {
                    include: {
                        taxonomytaxonomy: {
                            include: {
                                taxonomy: true,
                                child: true,
                            },
                        },
                        parent: true,
                        taxonomy: true,
                    },
                },
            },
            where: { AND: [{ species_id: id }, { taxonomy: { type: { equals: GENUS } } }] },
        });

        if (r == null) {
            throw new Error(`Failed to find genus for species with id ${id}.`);
        } else {
            return r;
        }
    };

    // eslint-disable-next-line prettier/prettier
    return pipe(
        TE.tryCatch(tree, handleError),
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
    const extractSpeciesIds = (tt: TaxonomyTree[]): number[] =>
        tt.reduce((acc, t) => {
            const more = t.taxonomy.flatMap((s) => s.speciestaxonomy.map((st) => st.species_id));
            acc.push(...more);
            return acc;
        }, new Array<number>());

    const get = (ids: number[]) => {
        return getSpecies([{ id: { in: ids } }]);
    };

    // eslint-disable-next-line prettier/prettier
    return pipe(
        taxonomyForId(id),
        TE.map(extractSpeciesIds),
        TE.map((x) => {
            console.log('FOOOOOOO: ' + id + '  -  ' + x);
            return x;
        }),
        TE.chain(get),
    );
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
            where: { id: !f.id ? -1 : f.id },
            update: {
                name: f.name,
                description: f.description,
            },
            create: {
                name: f.name,
                description: f.description,
                type: f.type,
            },
        });
    return pipe(
        TE.tryCatch(upsert, handleError),
        TE.map((sp) => sp.id),
    );
};
