import { species, speciestaxonomy, taxonomy, taxonomyalias, taxonomytaxonomy } from '@prisma/client';
import * as E from 'fp-ts/lib/Either';
import { pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import * as t from 'io-ts';
import { AliasApi, SimpleSpecies } from './apitypes';

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
    throw new Error(`Got an invalid taxonomy type: '${JSON.stringify(e, null, ' ')}'.`);
};

export type TaxonomyEntry = {
    id: number;
    name: string;
    description: string;
    type: TaxonomyType;
    parent: O.Option<TaxonomyEntry>;
};

export type TaxonomyEntryNoParent = Omit<TaxonomyEntry, 'parent'>;

export const EMPTY_TAXONOMYENTRY: TaxonomyEntry = {
    description: '',
    id: -1,
    name: '',
    type: 'family',
    parent: O.none,
};

export type DBTaxonomyWithParent =
    | (taxonomy & {
          parent?: taxonomy | null;
      })
    | null;

export const toTaxonomyEntry = (t: DBTaxonomyWithParent): TaxonomyEntry => {
    if (t == undefined) return EMPTY_TAXONOMYENTRY;

    return {
        id: t.id,
        description: t.description == null ? '' : t.description,
        name: t.name,
        type: pipe(TaxonomyTypeT.decode(t.type), E.getOrElse(invalidTaxonomyType)),
        parent: pipe(t.parent, O.fromNullable, O.map(toTaxonomyEntry)),
    };
};

export type FGS = {
    family: TaxonomyEntryNoParent;
    genus: TaxonomyEntryNoParent;
    section: O.Option<TaxonomyEntryNoParent>;
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

export type Genus = Omit<TaxonomyEntry, 'parent'>;

export type FamilyWithGenera = TaxonomyEntry & {
    // children: taxonomytaxonomy[];
    genera: Genus[];
    // taxonomytaxonomy: (taxonomytaxonomy & {
    //     child: taxonomy;
    // })[];
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
    parent: O.Option<TaxonomyEntry>;
};

export type FamilyUpsertFields = Omit<TaxonomyUpsertFields, 'species' | 'parent'> & {
    genera: Genus[];
};

export type SectionApi = {
    id: number;
    name: string;
    description: string;
    species: SimpleSpecies[];
    aliases: AliasApi[];
};
