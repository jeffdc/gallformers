import { species, speciestaxonomy, taxonomy, taxonomyalias, taxonomytaxonomy } from '@prisma/client';
import { identity, pipe } from 'fp-ts/lib/function';
import * as E from 'fp-ts/lib/Either';
import * as O from 'fp-ts/lib/Option';
import * as t from 'io-ts';

export const TaxonomyTypeT = t.keyof({
    family: null,
    section: null,
    genus: null,
});
export type TaxonomyType = t.TypeOf<typeof TaxonomyTypeT>;
export const FAMILY: TaxonomyType = 'family';
export const SECTION: TaxonomyType = 'section';
export const GENUS: TaxonomyType = 'genus';
export const invalidTaxonomyType = (e: t.Errors): TaxonomyType => {
    throw new Error(`Got an invalid taxonomy type: '${e}'.`);
};

export type TaxonomyEntry = {
    id: number;
    name: string;
    description: string;
    type: TaxonomyType;
};
export const EMPTY_TAXONOMYENTRY: TaxonomyEntry = {
    description: '',
    id: -1,
    name: '',
    type: 'family',
};

export const toTaxonomyEntry = (t: taxonomy): TaxonomyEntry => ({
    ...t,
    type: pipe(TaxonomyTypeT.decode(t.type), E.getOrElse(invalidTaxonomyType)),
});

export type FGS = {
    family: TaxonomyEntry;
    genus: TaxonomyEntry;
    section: O.Option<TaxonomyEntry>;
};
export const EMPTY_FGS: FGS = {
    family: EMPTY_TAXONOMYENTRY,
    genus: EMPTY_TAXONOMYENTRY,
    section: O.none,
};

export type TaxonomyTaxonomyApi = {
    id: number;
    parent_id: number;
    child_id: number;
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

export type TaxonomyWithParent = taxonomy & {
    parent: taxonomy;
};

export type TaxTreeForSpecies = speciestaxonomy & {
    taxonomy: taxonomy & {
        parent: taxonomy | null;
        taxonomy: taxonomy[];
        taxonomytaxonomy: (taxonomytaxonomy & {
            taxonomy: taxonomy;
            child: taxonomy;
        })[];
    };
};

export const EmptyTaxTreeForSpecies: TaxTreeForSpecies = {
    id: -1,
    species_id: -1,
    taxonomy_id: -1,
    taxonomy: {
        id: -1,
        description: '',
        name: '',
        parent: null,
        parent_id: null,
        taxonomy: [],
        taxonomytaxonomy: [],
        type: '',
    },
};

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

/**
 * The id should be set to any number less than 0 to indicate a new record.
 */
export type TaxonomyUpsertFields = {
    id: number;
    name: string;
    description: string;
    type: TaxonomyType;
    species: number[];
};
