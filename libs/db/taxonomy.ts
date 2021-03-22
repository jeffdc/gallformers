import { Prisma } from '@prisma/client';
import { constant, flow, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import * as TE from 'fp-ts/lib/TaskEither';
import { TaskEither } from 'fp-ts/lib/TaskEither';
import {
    ALL_FAMILY_TYPES,
    DeleteResult,
    GallTaxon,
    HostTaxon,
    FamilyGallTypesTuples,
    FamilyHostTypesTuple,
    FamilyTypesTuple,
    SimpleSpecies,
    SpeciesApi,
} from '../api/apitypes';
import {
    FAMILY,
    FamilyTaxonomy,
    FGS,
    GENUS,
    SECTION,
    TaxonomyEntry,
    TaxonomyTree,
    TaxonomyUpsertFields,
    toTaxonomyEntry,
} from '../api/taxonomy';
import { logger } from '../utils/logger';
import { ExtractTFromPromise } from '../utils/types';
import { handleError } from '../utils/util';
import db from './db';
import { getSpecies } from './species';
import { extractId } from './utils';

/**
 * Fetch a TaxonomyEntry by taxonomy id.
 * @param id
 */
export const taxonomyEntryById = (id: number): TaskEither<Error, O.Option<TaxonomyEntry>> => {
    const tax = () =>
        db.taxonomy.findFirst({
            where: { id: { equals: id } },
        });

    // eslint-disable-next-line prettier/prettier
    return pipe(
        TE.tryCatch(tax, handleError),
        TE.map((t) => pipe(t, O.fromNullable, O.map(toTaxonomyEntry))),
    );
};

export const taxonomyByName = (name: string): TaskEither<Error, O.Option<TaxonomyEntry>> => {
    return pipe(
        TE.tryCatch(() => db.taxonomy.findFirst({ where: { name: { equals: name } } }), handleError),
        TE.map((t) => pipe(t, O.fromNullable, O.map(toTaxonomyEntry))),
    );
};

/**
 * Fetch a taxonomy tree for a taxonomy id.
 * @param id
 */
export const taxonomyTreeForId = (id: number): TaskEither<Error, O.Option<TaxonomyTree>> => {
    const sps = () =>
        db.taxonomy.findFirst({
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

    // eslint-disable-next-line prettier/prettier
    return pipe(
        TE.tryCatch(sps, handleError),
        TE.map(O.fromNullable),
    );
};

/**
 * Fetch all families of the given type.
 * @param types the type of family to fetch
 * @see FamilyTypesTuple @see FamilyGallTypesTuples @see FamilyHostTypesTuple @see ALL_FAMILY_TYPES
 */
export const allFamilies = (
    types: FamilyTypesTuple | FamilyGallTypesTuples | FamilyHostTypesTuple = ALL_FAMILY_TYPES,
): TaskEither<Error, TaxonomyEntry[]> => {
    const families = () =>
        db.taxonomy.findMany({
            orderBy: { name: 'asc' },
            where: { description: { in: [...types] } },
        });

    return pipe(
        TE.tryCatch(families, handleError),
        TE.map((f) => f.map(toTaxonomyEntry)),
    );
};

/**
 * Fetch all genera for the given taxon.
 * @param taxon
 */
export const allGenera = (taxon: typeof GallTaxon | typeof HostTaxon): TaskEither<Error, TaxonomyEntry[]> => {
    const genera = () =>
        db.taxonomy.findMany({
            orderBy: { name: 'asc' },
            where: { AND: [{ type: GENUS }, { speciestaxonomy: { some: { species: { taxoncode: taxon } } } }] },
        });

    return pipe(
        TE.tryCatch(genera, handleError),
        TE.map((g) => g.map(toTaxonomyEntry)),
    );
};

/**
 * Fetch all of the Sections.
 * @returns
 */
export const allSections = (): TaskEither<Error, TaxonomyEntry[]> => {
    const sections = () =>
        db.taxonomy.findMany({
            include: { parent: true },
            orderBy: { name: 'asc' },
            where: { type: SECTION },
        });

    return pipe(
        TE.tryCatch(sections, handleError),
        TE.map((f) => f.map(toTaxonomyEntry)),
    );
};

/**
 * A species level taxonomy will consist of:
 * - a Genus
 * - a Family
 * - optionally a Section
 * @param id
 */
export const taxonomyForSpecies = (id: number): TaskEither<Error, FGS> => {
    const tree = () => {
        const r = db.speciestaxonomy
            .findFirst({
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
            })
            .then((r) => {
                if (r == null) throw new Error(`Failed to find genus for species with id ${id}.`);

                return r;
            });

        return r;
    };

    const toFGS = (tax: ExtractTFromPromise<ReturnType<typeof tree>>): FGS => {
        const genus = tax.taxonomy;
        const family = tax.taxonomy.parent;
        const section = O.fromNullable(tax.taxonomy.taxonomy.find((t) => t.type === SECTION));

        if (genus == null || family == null) {
            const msg = `Species with id ${id} is missing its family or genus.`;
            logger.error(msg);
            throw new Error(msg);
        }

        return {
            family: toTaxonomyEntry(family),
            genus: toTaxonomyEntry(genus),
            section: pipe(section, O.map(toTaxonomyEntry)),
        };
    };

    // eslint-disable-next-line prettier/prettier
    return pipe(
        TE.tryCatch(tree, handleError),
        TE.map(toFGS),
    );
};

/**
 * Fetches either the gall or host families and all of the children in the taxonomy.
 * @param gall true for gall families, false for host families
 */
export const getFamiliesWithSpecies = (gall: boolean) => (): TaskEither<Error, FamilyTaxonomy[]> => {
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

/**
 * Fetches all of the ids for all of the families.
 */
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

/**
 * Fetches all of the species for a given family.
 * @param id the family to fetch species for
 */
export const getAllSpeciesForFamily = (id: number): TaskEither<Error, SpeciesApi[]> => {
    const extractSpeciesIds = (tt: TaxonomyTree): number[] =>
        tt.taxonomy.flatMap((s) => s.speciestaxonomy.map((st) => st.species_id));

    const get = (ids: number[]) => getSpecies([{ id: { in: ids } }]);

    // eslint-disable-next-line prettier/prettier
    return pipe(
        taxonomyTreeForId(id),
        TE.map(flow(O.fold(constant([]), extractSpeciesIds))),
        TE.chain(get),
    );
};

export const getAllSpeciesForSection = (id: number): TaskEither<Error, SimpleSpecies[]> => {
    const sectionSpecies = (): Promise<SimpleSpecies[]> =>
        db.speciestaxonomy
            .findMany({
                where: { taxonomy_id: id },
                include: { species: true },
            })
            .then((st) => st.map((s) => ({ ...s.species } as SimpleSpecies)));

    return pipe(TE.tryCatch(sectionSpecies, handleError));
};

const taxonomyDeleteSteps = (id: number) => {
    return [
        db.speciestaxonomy.deleteMany({
            where: { taxonomy_id: id },
        }),
        db.taxonomy.deleteMany({
            where: { id: id },
        }),
    ];
};

/**
 * Delete the given taxonomy entry. If the taxoomy entry is a Family, then the delete will cascade to species and
 * delete species that are assigned to that family. So be careful!
 * @param id
 */
export const deleteTaxonomyEntry = (id: number): TaskEither<Error, DeleteResult> => {
    const toDeleteResult = (batch: Prisma.BatchPayload[]): DeleteResult => {
        return {
            type: 'taxonomy',
            name: id.toString(),
            count: batch.reduce((acc, v) => acc + v.count, 0),
        };
    };

    return pipe(
        TE.tryCatch(() => db.$transaction(taxonomyDeleteSteps(id)), handleError),
        TE.map(toDeleteResult),
    );
};

const connectSpecies = (f: TaxonomyUpsertFields) => f.species.map((s) => ({ species: { connect: { id: s } } }));

/**
 * Update or insert a Taxonomy entry.
 * @param f
 * @returns the count of the number of records added, will be 1 for success and 0 for a failure
 */
export const upsertTaxonomy = (f: TaxonomyUpsertFields): TaskEither<Error, TaxonomyEntry> => {
    console.log(`${JSON.stringify(f, null, '  ')}`);
    const connectParentOrNot = pipe(
        f.parent,
        O.fold(
            () => ({}),
            (p) => ({ connect: { id: p.id } }),
        ),
    );

    const upsert = () =>
        db.taxonomy.upsert({
            where: { id: f.id },
            update: {
                name: f.name,
                description: f.description,
                speciestaxonomy: {
                    deleteMany: { taxonomy_id: f.id },
                    create: connectSpecies(f),
                },
                parent: connectParentOrNot,
            },
            create: {
                name: f.name,
                description: f.description,
                type: f.type,
                speciestaxonomy: {
                    create: connectSpecies(f),
                },
                parent: connectParentOrNot,
            },
        });

    // eslint-disable-next-line prettier/prettier
    return pipe(
        TE.tryCatch(upsert, handleError),
        TE.map(toTaxonomyEntry),
    );
};
