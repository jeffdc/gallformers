import { Prisma, PrismaPromise, species, speciestaxonomy, taxonomy, taxonomyalias, taxonomytaxonomy } from '@prisma/client';
import * as O from 'fp-ts/lib/Option';
import * as TE from 'fp-ts/lib/TaskEither';
import { pipe } from 'fp-ts/lib/function';
import {
    ALL_FAMILY_TYPES,
    AliasApi,
    DeleteResult,
    EMPTY_TAXONOMYENTRY,
    FGS,
    FamilyAPI,
    FamilyGallTypesTuples,
    FamilyHostTypesTuple,
    FamilyTypesTuple,
    FamilyUpsertFields,
    GeneraMoveFields,
    Genus,
    SectionApi,
    SimpleSpecies,
    TaxonCodeValues,
    TaxonomyEntry,
    TaxonomyType,
    TaxonomyTypeValues,
    TaxonomyUpsertFields,
    asTaxonomyType,
} from '../api/apitypes';
import { logger } from '../utils/logger.ts';
import { ExtractTFromPromise } from '../utils/types';
import { handleError } from '../utils/util';
import db from './db';
import { extractId } from './utils';

export type TaxonomyTree = taxonomy & {
    parent: taxonomy | null;
    speciestaxonomy: (speciestaxonomy & {
        species: species;
    })[];
    taxonomy: (taxonomy & {
        speciestaxonomy: (speciestaxonomy & {
            species: species;
        })[];
        taxonomy: taxonomy[];
        taxonomyalias: taxonomyalias[];
        taxonomytaxonomy: taxonomytaxonomy[];
    })[];
    taxonomyalias: taxonomyalias[];
};

export type FamilyTaxonomy = taxonomy & {
    taxonomytaxonomy: (taxonomytaxonomy & {
        child: taxonomy & {
            speciestaxonomy: (speciestaxonomy & {
                species: species;
            })[];
        };
    })[];
};

type DBTaxonomyWithParent =
    | (taxonomy & {
          parent?: taxonomy | null;
      })
    | null;

const toTaxonomyEntry = (dbTax: DBTaxonomyWithParent): TaxonomyEntry => {
    if (dbTax == undefined) return EMPTY_TAXONOMYENTRY;

    return {
        id: dbTax.id,
        description: dbTax.description == null ? '' : dbTax.description,
        name: dbTax.name,
        // type: decodeWithDefault(TaxonomyTypeSchema.decode(dbTax.type), TaxonomyTypeValues.GENUS),
        type: asTaxonomyType(dbTax.type),
        parent: pipe(dbTax.parent, O.fromNullable, O.map(toTaxonomyEntry)),
    };
};
/**
 * Fetch a TaxonomyEntry by taxonomy id.
 * @param id
 */
export const taxonomyEntryById = (id: number): TE.TaskEither<Error, TaxonomyEntry[]> => {
    const tax = () =>
        db.taxonomy.findMany({
            where: { id: { equals: id } },
            include: { parent: true },
        });

    // eslint-disable-next-line prettier/prettier
    return pipe(
        TE.tryCatch(tax, handleError),
        TE.map((ts) => ts.map(toTaxonomyEntry)),
    );
};

export const taxonomyByName = (name: string): TE.TaskEither<Error, TaxonomyEntry[]> => {
    return pipe(
        TE.tryCatch(() => db.taxonomy.findMany({ where: { name: { equals: name } } }), handleError),
        TE.map((ts) => ts.map(toTaxonomyEntry)),
    );
};

export const familyById = (id: number): TE.TaskEither<Error, FamilyAPI[]> => {
    return pipe(
        TE.tryCatch(
            () =>
                db.taxonomy.findMany({
                    include: { taxonomy: true },
                    where: { AND: [{ id: id }, { type: { equals: TaxonomyTypeValues.FAMILY } }] },
                }),
            handleError,
        ),
        TE.map((ts) =>
            ts.map((t) => ({
                ...toTaxonomyEntry(t),
                genera: t.taxonomy.map(toTaxonomyEntry),
            })),
        ),
    );
};

export const familyByName = (name: string): TE.TaskEither<Error, TaxonomyEntry[]> => {
    return pipe(
        TE.tryCatch(
            () =>
                db.taxonomy.findMany({
                    include: { taxonomy: true },
                    where: { AND: [{ name: { equals: name } }, { type: { equals: TaxonomyTypeValues.FAMILY } }] },
                }),
            handleError,
        ),
        TE.map((ts) =>
            ts.map((t) => ({
                ...toTaxonomyEntry(t),
                genera: t.taxonomy.map(toTaxonomyEntry),
            })),
        ),
    );
};

/**
 * Fetch a taxonomy tree for a taxonomy id.
 * @param id
 */
export const taxonomyTreeForId = (id: number): TE.TaskEither<Error, O.Option<TaxonomyTree>> => {
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
): TE.TaskEither<Error, TaxonomyEntry[]> => {
    const families = () =>
        db.taxonomy.findMany({
            orderBy: { name: 'asc' },
            where: { AND: [{ description: { in: [...types] } }, { type: { equals: 'family' } }] },
        });

    return pipe(
        TE.tryCatch(families, handleError),
        TE.map((f) => f.map(toTaxonomyEntry)),
    );
};

export const allFamiliesWithGenera = (): TE.TaskEither<Error, FamilyAPI[]> => {
    const families = () =>
        db.taxonomy.findMany({
            include: {
                taxonomy: true,
            },
            orderBy: { name: 'asc' },
            where: { type: { equals: 'family' } },
        });

    return pipe(
        TE.tryCatch(families, handleError),
        TE.map((taxs) =>
            taxs.map((tax) => ({
                ...toTaxonomyEntry(tax),
                genera: tax.taxonomy.map(toTaxonomyEntry),
            })),
        ),
    );
};

/**
 * Fetch all genera for the given taxon.
 * @param taxon
 * @param includeEmpty defaults to false, if true then any genera that are not assigned to some species will
 * also be returned. It is generally useful to not show empty genera in the main (non-Admin) UI but in the admin
 * UI it is necessary so that new species can be assigned to them.
 */
export const allGenera = (taxon: TaxonCodeValues, includeEmpty = false): TE.TaskEither<Error, TaxonomyEntry[]> => {
    const genera = () =>
        db.taxonomy.findMany({
            include: { parent: true },
            orderBy: { name: 'asc' },
            where: {
                OR: includeEmpty
                    ? [
                          {
                              AND: [
                                  { type: TaxonomyTypeValues.GENUS },
                                  { speciestaxonomy: { some: { species: { taxoncode: taxon } } } },
                              ],
                          },
                          { AND: [{ type: TaxonomyTypeValues.GENUS }, { name: 'Unknown' }] },
                          // this clause will pull in all genera that are not yet assigned to any species.
                          { AND: [{ type: TaxonomyTypeValues.GENUS }, { speciestaxonomy: { none: {} } }] },
                      ]
                    : [
                          {
                              AND: [
                                  { type: TaxonomyTypeValues.GENUS },
                                  { speciestaxonomy: { some: { species: { taxoncode: taxon } } } },
                              ],
                          },
                          { AND: [{ type: TaxonomyTypeValues.GENUS }, { name: 'Unknown' }] },
                      ],
            },
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
export const allSections = (): TE.TaskEither<Error, TaxonomyEntry[]> => {
    const sections = () =>
        db.taxonomy.findMany({
            include: { parent: true },
            orderBy: { name: 'asc' },
            where: { type: TaxonomyTypeValues.SECTION },
        });

    return pipe(
        TE.tryCatch(sections, handleError),
        TE.map((f) => f.map(toTaxonomyEntry)),
    );
};

export const allSectionIds = (): TE.TaskEither<Error, string[]> =>
    pipe(
        allSections(),
        TE.map((sections) => sections.map((s) => s.id.toString())),
    );

/**
 * A species level taxonomy will consist of:
 * - a Genus
 * - a Family
 * - optionally a Section
 * @param id
 */
export const taxonomyForSpecies = (id: number): TE.TaskEither<Error, FGS> => {
    const tree = () => {
        const r = db.speciestaxonomy
            .findMany({
                include: {
                    taxonomy: {
                        include: {
                            parent: true,
                        },
                    },
                },
                where: { species_id: id },
            })
            .then((r) => {
                if (r == null) throw new Error(`Failed to find genus for species with id ${id}.`);

                return r;
            });

        return r;
    };

    const toFGS = (tax: ExtractTFromPromise<ReturnType<typeof tree>>): FGS => {
        const genus = tax.find((t) => t.taxonomy.type === TaxonomyTypeValues.GENUS)?.taxonomy;
        const family = genus?.parent;
        const section = O.fromNullable(tax.find((t) => t.taxonomy.type === TaxonomyTypeValues.SECTION)?.taxonomy);

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
export const getFamiliesWithSpecies =
    (gall: boolean, undescribedOnly = false) =>
    (): TE.TaskEither<Error, FamilyTaxonomy[]> => {
        const filterOnlyUndescribed = (fs: FamilyTaxonomy[]) => {
            return fs
                .map(
                    (family) =>
                        // filter out all genera that do not have an undescribed species in them
                        ({
                            ...family,
                            taxonomytaxonomy: family.taxonomytaxonomy.filter((genus) => genus.child.speciestaxonomy.length > 0),
                        }) as FamilyTaxonomy,
                    // filter out famlies that have no genera in them after the above filter
                )
                .filter((f) => f.taxonomytaxonomy.length > 0);
        };

        const fams = async () => {
            const where = gall
                ? [{ type: TaxonomyTypeValues.FAMILY }, { description: { not: 'Plant' } }]
                : [{ type: TaxonomyTypeValues.FAMILY }, { description: { equals: 'Plant' } }];

            return db.taxonomy
                .findMany({
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
                                            where: !undescribedOnly
                                                ? {}
                                                : {
                                                      species: {
                                                          gallspecies: { some: { gall: { undescribed: { equals: true } } } },
                                                      },
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
                })
                .then((fs) => (!undescribedOnly ? fs : filterOnlyUndescribed(fs)));
        };

        return TE.tryCatch(fams, handleError);
    };

/**
 * Fetches all of the ids for all of the families.
 */
export const allFamilyIds = (): TE.TaskEither<Error, string[]> => {
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

export const allGenusIds = (): TE.TaskEither<Error, string[]> => {
    const genera = () =>
        db.taxonomy.findMany({
            select: { id: true },
            where: { type: { equals: 'genus' } },
        });

    return pipe(
        TE.tryCatch(genera, handleError),
        TE.map((x) => x.map(extractId).map((n) => n.toString())),
    );
};

export const getAllSpeciesForSectionOrGenus = (id: number): TE.TaskEither<Error, SimpleSpecies[]> => {
    const sectionSpecies = () =>
        db.speciestaxonomy.findMany({
            where: { taxonomy_id: id },
            include: { species: true },
            orderBy: { species: { name: 'asc' } },
        });

    return pipe(
        TE.tryCatch(sectionSpecies, handleError),
        TE.map((s) => s.map((sp) => ({ ...sp.species }) as SimpleSpecies)),
    );
};

/**
 * Fetch all of the genera for the given family id.
 * @param id the id of the family
 * @returns an array of the genera
 */
export const getGeneraForFamily = (id: number): TE.TaskEither<Error, Genus[]> => {
    const familyGenera = () =>
        db.taxonomytaxonomy.findMany({
            where: { taxonomy_id: id },
            include: { child: true },
        });

    return pipe(
        TE.tryCatch(familyGenera, handleError),
        TE.map((gs) =>
            gs.map((g) => ({
                id: g.child.id,
                name: g.child.name,
                type: g.child.type as TaxonomyType,
                description: g.child.description ?? '',
            })),
        ),
    );
};

export const sectionById = (id: number): TE.TaskEither<Error, SectionApi[]> => {
    const section = () =>
        db.taxonomy.findMany({
            select: {
                id: true,
                name: true,
                description: true,
                speciestaxonomy: { include: { species: true } },
                taxonomyalias: { include: { alias: true } },
            },
            where: { AND: [{ id: { equals: id } }, { type: { equals: TaxonomyTypeValues.SECTION } }] },
        });

    return pipe(
        TE.tryCatch(section, handleError),
        TE.map((ts) =>
            ts.map((t) => ({
                ...t,
                description: t.description ?? '',
                species: t?.speciestaxonomy.map((sp) => ({ ...sp.species }) as SimpleSpecies),
                aliases: t.taxonomyalias.map((a) => ({ ...a.alias }) as AliasApi),
            })),
        ),
    );
};

export const sectionByName = (name: string): TE.TaskEither<Error, SectionApi[]> => {
    return pipe(
        TE.tryCatch(
            () =>
                db.taxonomy.findMany({
                    select: {
                        id: true,
                        name: true,
                        description: true,
                        speciestaxonomy: { include: { species: true } },
                        taxonomyalias: { include: { alias: true } },
                    },
                    where: { AND: [{ name: { equals: name } }, { type: { equals: TaxonomyTypeValues.SECTION } }] },
                }),
            handleError,
        ),
        TE.map((ts) =>
            ts.map((t) => ({
                ...t,
                description: t.description ?? '',
                species: t?.speciestaxonomy.map((sp) => ({ ...sp.species }) as SimpleSpecies),
                aliases: t.taxonomyalias.map((a) => ({ ...a.alias }) as AliasApi),
            })),
        ),
    );
};
/**
 * Delete the given taxonomy entry. If the taxoomy entry is a Family, then the delete will cascade to species and
 * delete species that are assigned to that family. So be careful!
 * @param id
 */
export const deleteTaxonomyEntry = (id: number): TE.TaskEither<Error, DeleteResult> => {
    const doDelete = () => {
        // have to do raw calls since Prisma does not support cascade deletion.
        const delSpeciesSql = `
                DELETE FROM species
                    WHERE id IN (
                    SELECT s.id
                    FROM taxonomy AS f
                        INNER JOIN
                        taxonomy AS g ON f.id = g.parent_id
                        INNER JOIN
                        speciestaxonomy AS st ON st.taxonomy_id = g.id
                        INNER JOIN
                        species AS s ON s.id = st.species_id
                    WHERE f.id = ${id}
                );
            `;
        const delTaxSql = `DELETE FROM taxonomy WHERE id = ${id}`;
        return db.$transaction([db.$executeRaw(Prisma.sql([delSpeciesSql])), db.$executeRaw(Prisma.sql([delTaxSql]))]);
    };

    const toDeleteResult = (t: number[]): DeleteResult => {
        return {
            type: 'taxonomy',
            name: id.toString(),
            count: t.reduce((t, x) => t + x, 0),
        };
    };

    // eslint-disable-next-line prettier/prettier
    return pipe(
        TE.tryCatch(doDelete, handleError),
        TE.map(toDeleteResult),
    );
};

const connectSpecies = (f: TaxonomyUpsertFields) => f.species.map((s) => ({ species: { connect: { id: s } } }));

/**
 * Update or insert a Taxonomy entry.
 * @param f
 * @returns the count of the number of records added, will be 1 for success and 0 for a failure
 */
export const upsertTaxonomy = (f: TaxonomyUpsertFields): TE.TaskEither<Error, TaxonomyEntry> => {
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

const updateExistingGenera = (fam: FamilyUpsertFields) => {
    const r = fam.genera
        .filter((g) => g.id > 0) // if it is new then we do not need to worry about it
        .map((g) =>
            db.taxonomy.update({
                where: { id: g.id },
                data: {
                    name: g.name,
                    description: g.description,
                },
            }),
        );
    return r;
};

const updateExistingSpecies = (fam: FamilyUpsertFields) => {
    // I tried to do this with prisma but could not figure it out...
    return fam.genera.map((g) => {
        const sql = `UPDATE species
                SET name = [REPLACE](name, SUBSTRING(name, 1, INSTR(name, ' ') - 1), '${g.name}') 
            WHERE id IN (
                SELECT st.species_id
                    FROM taxonomy AS t
                        INNER JOIN
                        speciestaxonomy AS st ON t.id = st.taxonomy_id
                    WHERE t.id = ${g.id} 
            );`;
        return db.$executeRaw(Prisma.sql([sql]));
    });
};

const createGenera = (fam: FamilyUpsertFields) => {
    if (fam.genera.length <= 0) {
        // this is dumb but Prisma requires a custom type PrismaPromise that is impossible to construct
        // from the outside - not sure why I keep bothering with Prisma...
        return db.taxonomy.count({ where: { id: 1 } });
    }

    return db.taxonomy.update({
        where: { id: fam.id },
        data: {
            name: fam.name,
            description: fam.description,
            taxonomytaxonomy: {
                connectOrCreate: fam.genera.map((g) => ({
                    where: {
                        taxonomy_id_child_id: {
                            child_id: g.id,
                            taxonomy_id: fam.id,
                        },
                    },
                    create: {
                        child: {
                            connectOrCreate: {
                                where: {
                                    id: g.id,
                                },
                                create: {
                                    name: g.name,
                                    type: g.type,
                                    description: g.description,
                                    parent_id: fam.id,
                                },
                            },
                        },
                    },
                })),
            },
        },
    });
};

const familyUpdateSteps = (fam: FamilyUpsertFields): PrismaPromise<unknown>[] => {
    const deltax = `DELETE FROM taxonomy
        WHERE parent_id = ${fam.id} AND 
            id NOT IN (${fam.genera.map((g) => g.id).join(',')});`;

    const delsp = `DELETE FROM species
        WHERE id IN (
        SELECT species_id
        FROM speciestaxonomy AS st
            INNER JOIN
            taxonomy AS t ON t.id = st.taxonomy_id
        WHERE t.parent_id = ${fam.id} AND 
            id NOT IN (${fam.genera.map((g) => g.id).join(',')}) 
    );`;

    return [
        // delete any genera that are not part of the update
        db.$executeRaw(Prisma.sql([delsp])),
        db.$executeRaw(Prisma.sql([deltax])),

        // update any species names that are part of the updated genera
        ...updateExistingSpecies(fam),

        // update the actual genera entries in the taxonomy
        ...updateExistingGenera(fam),

        // now we can setup relationships and create new genera
        createGenera(fam),
    ];
};

const familyCreate = async (f: FamilyUpsertFields): Promise<number> => {
    // I do not think it is possible to create the Family AND the related Genera is a single transaction
    // using Prisma and the current DB schema. The parent relationship on taxonomy seems to make this
    // impossible. So we will have to do this as multiple steps without a transaction. :(

    // insert the family and return its ID
    const famid = await db.taxonomy.create({
        data: {
            name: f.name,
            description: f.description,
            type: f.type,
        },
        select: { id: true },
    });

    return famid.id;
};

const generaCreate =
    (f: FamilyUpsertFields) =>
    (fid: number): TE.TaskEither<Error, unknown> => {
        // add the genera and relationships
        const doCreate = () =>
            db.$transaction(
                f.genera.map((g) =>
                    db.taxonomytaxonomy.create({
                        data: {
                            child: {
                                create: {
                                    name: g.name,
                                    description: g.description,
                                    type: TaxonomyTypeValues.GENUS,
                                    parent_id: fid,
                                },
                            },
                            taxonomy: {
                                connect: {
                                    id: fid,
                                },
                            },
                        },
                    }),
                ),
            );

        return TE.tryCatch(doCreate, handleError);
    };

/**
 * Update or insert a Family Taxonomy entry.
 * @param f
 * @returns the count of the number of records added, will be 1 for success and 0 for a failure
 */
export const upsertFamily = (f: FamilyUpsertFields): TE.TaskEither<Error, TaxonomyEntry> => {
    const updateFamilyTx = TE.tryCatch(() => db.$transaction(familyUpdateSteps(f)), handleError);

    // eslint-disable-next-line prettier/prettier
    const createFamily = pipe(
        TE.tryCatch(() => familyCreate(f), handleError),
        TE.chain(generaCreate(f)),
    );

    const getFam = () => {
        return pipe(
            familyByName(f.name),
            TE.map((fs) => O.fromNullable(fs[0])),
        );
    };

    return pipe(
        f.id < 0 ? createFamily : updateFamilyTx,
        TE.chain(getFam),
        TE.fold(
            (e) => TE.left(e),
            (s) =>
                pipe(
                    s,
                    O.fold(
                        () => TE.left(new Error('Failed to get upserted data.')),
                        (te) => TE.right(te),
                    ),
                ),
        ),
        TE.map((x) => x),
    );
};

export const moveGenera = (f: GeneraMoveFields): TE.TaskEither<Error, FamilyAPI[]> => {
    const doMove = () =>
        db.$transaction([
            // reassign the parent to the new family for all of the passed in genera
            db.taxonomy.updateMany({
                where: { id: { in: f.genera } },
                data: {
                    parent_id: f.newFamilyId,
                },
            }),
            // delete all mappings between the old family and the genera
            db.taxonomytaxonomy.deleteMany({
                where: { child_id: { in: f.genera }, taxonomy_id: f.oldFamilyId },
            }),
            // add mappings between the new family and the genera
            ...f.genera.map((g) =>
                db.taxonomytaxonomy.create({
                    data: {
                        taxonomy_id: f.newFamilyId,
                        child_id: g,
                    },
                }),
            ),
        ]);

    // eslint-disable-next-line prettier/prettier
    return pipe(
        TE.tryCatch(doMove, handleError),
        TE.chain(allFamiliesWithGenera),
    );
};

const taxonomySearch =
    (taxonType: TaxonomyType) =>
    (s: string): TE.TaskEither<Error, TaxonomyEntry[]> => {
        const doSearch = () =>
            db.taxonomy.findMany({
                where: {
                    AND: [{ name: { contains: s } }, { type: taxonType }],
                },
            });

        return pipe(
            TE.tryCatch(doSearch, handleError),
            TE.map((g) => g.map(toTaxonomyEntry)),
        );
    };

export const generaSearch = taxonomySearch(TaxonomyTypeValues.GENUS);
export const sectionSearch = taxonomySearch(TaxonomyTypeValues.SECTION);
export const familySearch = taxonomySearch(TaxonomyTypeValues.FAMILY);
