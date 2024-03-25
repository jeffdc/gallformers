/**
 * Types for calling the APIs. These are to be used by browser code when it calls the APIs so all database stuff
 * must stay out of here.
 */
import * as Eq from 'fp-ts/lib/Eq.js';
import * as O from 'fp-ts/lib/Option';
import { Option } from 'fp-ts/lib/Option';

export type Deletable = {
    delete?: boolean;
};

export const GALL_FAMILY_TYPES = [
    'Aphid',
    'Bacteria',
    'Beetle',
    'Fly',
    'Fungus',
    'Midge',
    'Mite',
    'Moth',
    'Nematode',
    'Oomycete',
    'Psyllid',
    'Sawfly',
    'Scale',
    'Thrips',
    'True Bug',
    'Virus',
    'Wasp',
    'Unknown',
] as const;
export const HOST_FAMILY_TYPES = ['Plant'] as const;
export const ALL_FAMILY_TYPES = [
    'Aphid',
    'Bacteria',
    'Beetle',
    'Fly',
    'Fungus',
    'Midge',
    'Mite',
    'Moth',
    'Nematode',
    'Oomycete',
    'Plant',
    'Psyllid',
    'Sawfly',
    'Scale',
    'Thrips',
    'True Bug',
    'Virus',
    'Wasp',
    'Unknown',
] as const;
export type FamilyTypesTuple = typeof ALL_FAMILY_TYPES;
export type FamilyType = FamilyTypesTuple[number];
export type FamilyGallTypesTuples = typeof GALL_FAMILY_TYPES;
export type FamilyGallType = FamilyGallTypesTuples[number];
export type FamilyHostTypesTuple = typeof HOST_FAMILY_TYPES;
export type FamilyHostType = FamilyHostTypesTuple[number];

export type SpeciesUpsertFields = {
    id: number;
    name: string;
    datacomplete: boolean;
    aliases: AliasApi[];
    abundance: string | null | undefined;
    fgs: FGS;
    places: PlaceNoTreeApi[];
};

export type GallUpsertFields = SpeciesUpsertFields & {
    gallid: number; // if less than 0 then new
    hosts: number[];
    locations: number[];
    colors: number[];
    seasons: number[];
    shapes: number[];
    textures: number[];
    alignments: number[];
    walls: number[];
    cells: number[];
    forms: number[];
    detachable: DetachableApi;
    undescribed: boolean;
};

export type AbundanceApi = {
    id: number;
    abundance: string;
    description: string;
    reference: Option<string>;
};
// export const AbundanceApiSchema = t.type({
//     id: t.number,
//     abundance: t.string,
//     description: t.string,
//     reference: tt.option(t.string),
// });

export const EmptyAbundance: AbundanceApi = {
    id: -1,
    abundance: '',
    description: '',
    reference: O.none,
};

////////////////////////////////////////////////////////////////////
// Place Schemas and Types

// For now only these two until we support the Place hierarchy.
export const PLACE_TYPES = ['state', 'province'];

export const placeNoTreeApiEq: Eq.Eq<PlaceNoTreeApi> = {
    equals: (a, b) => a.code === b.code,
};

// export const PlaceNoTreeApiSchema = t.type({
//     id: t.number,
//     name: t.string,
//     code: t.string,
//     type: t.string,
// });

// export type PlaceNoTreeApi = t.TypeOf<typeof PlaceNoTreeApiSchema>;
export type PlaceNoTreeApi = {
    id: number;
    name: string;
    code: string;
    type: string;
};

export type PlaceNoTreeUpsertFields = PlaceNoTreeApi & Deletable;

export type PlaceApi = PlaceNoTreeApi & {
    parent: PlaceApi[];
    children: PlaceApi[];
};

export type PlaceWithHostsApi = PlaceApi & {
    hosts: HostSimple[];
};

////////////////////////////////////////////////////////////////////
// SimpleSpecies Schema and Type
export enum TaxonCodeValues {
    GALL = 'gall',
    PLANT = 'plant',
}

/** Given a string value, look up the proper TaxonCode. If the value is not one of the valid values then an error will be thrown. */
export const taxonCodeAsStringToValue = (tc?: string | null): TaxonCodeValues => {
    if (tc === TaxonCodeValues.GALL) {
        return TaxonCodeValues.GALL;
    } else if (tc === TaxonCodeValues.PLANT) {
        return TaxonCodeValues.PLANT;
    } else {
        throw new Error(`Invalid TaxonCode value detected: '${tc}'.`);
    }
};

export type SimpleSpecies = {
    id: number;
    taxoncode: TaxonCodeValues;
    name: string;
};

////////////////////////////////////////////////////////////////////
// Source Schemas and Types
export type SourceApi = {
    id: number;
    title: string;
    author: string;
    pubyear: string;
    link: string;
    citation: string;
    datacomplete: boolean;
    license: string;
    licenselink: string;
};
export type SpeciesSourceNoSourceApi = {
    id: number;
    species_id: number;
    source_id: number | null;
    description: string;
    useasdefault: number;
    externallink: string;
};
export type SpeciesSourceApi = SpeciesSourceNoSourceApi & { source: SourceApi };
export type SourceWithSpeciesApi = SourceApi & {
    species: SimpleSpecies[];
};
export type SourceWithSpeciesSourceApi = SourceApi & {
    speciessource: Omit<SpeciesSourceApi, 'source'>[];
};

////////////////////////////////////////////////////////////////////
// SpeciesSource Schemas and Types

export type SpeciesWithPlaces = SimpleSpecies & {
    places: PlaceNoTreeApi[];
};

////////////////////////////////////////////////////////////////////////////////
// Taxonomy Types
/**
 * There are three valid types in the taxonomy.
 */
export enum TaxonomyTypeValues {
    FAMILY = 'family',
    SECTION = 'section',
    GENUS = 'genus',
}
// export const TaxonomyTypeSchema = fromEnum<TaxonomyTypeValues>('TaxonomyTypeValues', TaxonomyTypeValues);
// export type TaxonomyType = t.TypeOf<typeof TaxonomyTypeSchema>;
export type TaxonomyType = 'family' | 'section' | 'genus';
export const asTaxonomyType = (possibleType?: string | null): TaxonomyType => {
    if (possibleType === TaxonomyTypeValues.FAMILY) {
        return TaxonomyTypeValues.FAMILY;
    } else if (possibleType === TaxonomyTypeValues.SECTION) {
        return TaxonomyTypeValues.SECTION;
    } else if (possibleType === TaxonomyTypeValues.GENUS) {
        return TaxonomyTypeValues.GENUS;
    } else {
        return TaxonomyTypeValues.FAMILY;
    }
};

/**
 * A general Taxonomy entry from the database. It can be recursive and this can lead to trouble with certain libraries etc.
 * So look at @see {TaxonomyEntryNoParent} as well.
 */
export interface TaxonomyEntry {
    id: number;
    name: string;
    type: TaxonomyType;
    description: string;
    parent: O.Option<TaxonomyEntry>;
}

export type TaxonomyEntryNoParent = {
    id: number;
    name: string;
    type: TaxonomyType;
    description: string;
};

export const EMPTY_TAXONOMYENTRY: TaxonomyEntry = {
    description: '',
    id: -1,
    name: '',
    type: TaxonomyTypeValues.FAMILY,
    parent: O.none,
};

export const EMPTY_GENUS: TaxonomyEntry = { ...EMPTY_TAXONOMYENTRY, type: TaxonomyTypeValues.GENUS };

export type FGS = {
    family: TaxonomyEntry;
    genus: TaxonomyEntry;
    section: Option<TaxonomyEntry>;
};

export type Genus = TaxonomyEntryNoParent;

export type FamilyAPI = TaxonomyEntryNoParent & {
    genera: Genus[];
};
export type SectionApi = Omit<TaxonomyEntryNoParent, 'type'> & {
    species: SimpleSpecies[];
    aliases: AliasApi[];
};
/**
 * The id should be set to any number less than 0 to indicate a new record.
 */

export type TaxonomyUpsertFields = TaxonomyEntry & {
    species: number[];
};

export type FamilyUpsertFields = Omit<TaxonomyUpsertFields, 'species' | 'parent'> & {
    genera: Genus[];
};

export type GeneraMoveFields = {
    oldFamilyId: number;
    newFamilyId: number;
    genera: number[];
};

////////////////////////////////////////////////////////////////////////////////////
// Image types
export type ImageBase = {
    default: boolean;
    creator: string;
    attribution: string;
    caption: string;
};

export enum ImageLicenseValues {
    NONE = '',
    PUBLIC_DOMAIN = 'Public Domain / CC0',
    CC_BY = 'CC-BY',
    ALL_RIGHTS = 'All Rights Reserved',
}
export type ImageLicenseType = '' | 'Public Domain / CC0' | 'CC-BY' | 'All Rights Reserved';
export const asImageLicense = (possibleLicense?: string | null): ImageLicenseType => {
    if (possibleLicense === ImageLicenseValues.PUBLIC_DOMAIN) {
        return ImageLicenseValues.PUBLIC_DOMAIN;
    } else if (possibleLicense === ImageLicenseValues.CC_BY) {
        return ImageLicenseValues.CC_BY;
    } else if (possibleLicense === ImageLicenseValues.ALL_RIGHTS) {
        return ImageLicenseValues.ALL_RIGHTS;
    } else {
        return ImageLicenseValues.NONE;
    }
};

export type ImageSource = {
    license: ImageLicenseType;
    licenselink: string;
    sourcelink: string;
    // source: Option<SourceWithSpeciesSourceApi>;
    source: SourceWithSpeciesSourceApi | null;
    source_id: number | null;
};

export type ImageAdditional = {
    id: number;
    path: string;
    uploader: string;
    lastchangedby: string;
    speciesid: number;
    small: string;
    medium: string;
    large: string;
    xlarge: string;
    original: string;
};

export type ImageNoSourceApi = ImageBase & ImageAdditional;

export type ImageApi = ImageNoSourceApi & ImageSource;

export type ImagePaths = {
    small: string[];
    medium: string[];
    large: string[];
    xlarge: string[];
    original: string[];
};

export type WithImages = {
    images: ImageApi[] | ImageNoSourceApi[];
};

export const COMMON_NAME = 'common';
export const SCIENTIFIC_NAME = 'scientific';

export type AliasApi = {
    id: number;
    name: string;
    type: string;
    description: string;
};

export const EmptyAlias: AliasApi = {
    id: -1,
    name: '',
    type: SCIENTIFIC_NAME,
    description: '',
};

export type SpeciesApi = SimpleSpecies &
    WithImages & {
        datacomplete: boolean;
        abundance: Option<AbundanceApi>;
        description: Option<string>; // to make the caller's life easier we will load the default if we can
        speciessource: SpeciesSourceApi[];
        aliases: AliasApi[];
        fgs: FGS;
    };

export const FILTER_FIELD_ALIGNMENTS = 'alignments';
export const FILTER_FIELD_CELLS = 'cells';
export const FILTER_FIELD_COLORS = 'colors';
export const FILTER_FIELD_FORMS = 'forms';
export const FILTER_FIELD_LOCATIONS = 'locations';
export const FILTER_FIELD_SEASONS = 'seasons';
export const FILTER_FIELD_SHAPES = 'shapes';
export const FILTER_FIELD_TEXTURES = 'textures';
export const FILTER_FIELD_WALLS = 'walls';
export const FILTER_FIELD_TYPES = [
    FILTER_FIELD_ALIGNMENTS,
    FILTER_FIELD_CELLS,
    FILTER_FIELD_COLORS,
    FILTER_FIELD_FORMS,
    FILTER_FIELD_LOCATIONS,
    FILTER_FIELD_SEASONS,
    FILTER_FIELD_SHAPES,
    FILTER_FIELD_TEXTURES,
    FILTER_FIELD_WALLS,
] as const;
export type FilterFieldTypeTuple = typeof FILTER_FIELD_TYPES;
export type FilterFieldType = FilterFieldTypeTuple[number];
export const asFilterFieldType = (f: string): FilterFieldType => {
    // Seems like there should be a better way to handle this and maintain types.
    switch (f) {
        case FILTER_FIELD_ALIGNMENTS:
            return FILTER_FIELD_ALIGNMENTS;
        case FILTER_FIELD_CELLS:
            return FILTER_FIELD_CELLS;
        case FILTER_FIELD_COLORS:
            return FILTER_FIELD_COLORS;
        case FILTER_FIELD_FORMS:
            return FILTER_FIELD_FORMS;
        case FILTER_FIELD_LOCATIONS:
            return FILTER_FIELD_LOCATIONS;
        case FILTER_FIELD_SEASONS:
            return FILTER_FIELD_SEASONS;
        case FILTER_FIELD_SHAPES:
            return FILTER_FIELD_SHAPES;
        case FILTER_FIELD_TEXTURES:
            return FILTER_FIELD_TEXTURES;
        case FILTER_FIELD_WALLS:
            return FILTER_FIELD_WALLS;
        default:
            throw new Error(`Invalid filter field type: '${f}'.`);
    }
};

export type FilterField = {
    id: number;
    field: string;
    description: Option<string>;
};

export enum FilterFieldTypeValue {
    ALIGNMENTS = 'alignments',
    CELLS = 'cells',
    COLORS = 'colors',
    FORMS = 'forms',
    LOCATIONS = 'locations',
    SEASONS = 'seasons',
    SHAPES = 'shapes',
    TEXTURES = 'textures',
    WALLS = 'walls',
}

export const asFilterType = (possibleFilterType?: string | null): FilterFieldTypeValue => {
    if (possibleFilterType === FilterFieldTypeValue.ALIGNMENTS) {
        return FilterFieldTypeValue.ALIGNMENTS;
    } else if (possibleFilterType === FilterFieldTypeValue.CELLS) {
        return FilterFieldTypeValue.CELLS;
    } else if (possibleFilterType === FilterFieldTypeValue.COLORS) {
        return FilterFieldTypeValue.COLORS;
    } else if (possibleFilterType === FilterFieldTypeValue.FORMS) {
        return FilterFieldTypeValue.FORMS;
    } else if (possibleFilterType === FilterFieldTypeValue.LOCATIONS) {
        return FilterFieldTypeValue.LOCATIONS;
    } else if (possibleFilterType === FilterFieldTypeValue.SEASONS) {
        return FilterFieldTypeValue.SEASONS;
    } else if (possibleFilterType === FilterFieldTypeValue.SHAPES) {
        return FilterFieldTypeValue.SHAPES;
    } else if (possibleFilterType === FilterFieldTypeValue.TEXTURES) {
        return FilterFieldTypeValue.TEXTURES;
    } else if (possibleFilterType === FilterFieldTypeValue.WALLS) {
        return FilterFieldTypeValue.WALLS;
    } else {
        return FilterFieldTypeValue.ALIGNMENTS;
    }
};

export type FilterFieldWithType = FilterField & {
    fieldType: FilterFieldType;
};

export type GallHost = {
    id: number;
    name: string;
    places: PlaceNoTreeApi[];
};

export type RandomGall = {
    id: number;
    name: string;
    undescribed: boolean;
    imagePath: string;
    creator: string;
    license: string;
    sourceLink: string;
    licenseLink: string;
};

// a cut down structure for the ID page
export type GallIDApi = WithImages & {
    id: number;
    name: string;
    datacomplete: boolean;
    alignments: string[];
    cells: string[];
    colors: string[];
    detachable: DetachableApi;
    forms: string[];
    locations: string[];
    places: string[];
    seasons: string[];
    shapes: string[];
    textures: string[];
    undescribed: boolean;
    walls: string[];
    family: string;
};

export type SourceUpsertFields = Deletable & {
    id: number;
    title: string;
    author: string;
    pubyear: string;
    link: string;
    citation: string;
    datacomplete: boolean;
    license: string;
    licenselink: string;
};

export type SpeciesSourceInsertFields = Deletable & {
    id: number;
    species: number;
    source: number;
    description: string;
    useasdefault: boolean;
    externallink: string;
};

export type GallHostUpdateFields = {
    gall: number;
    hosts: number[];
    rangeExclusions: PlaceNoTreeApi[];
};

export type DeleteResult = {
    type: string;
    name: string;
    count: number;
};

export type GlossaryEntryUpsertFields = Deletable & {
    id: number;
    word: string;
    definition: string;
    urls: string; // newline separated
};

export enum DetachableValues {
    NONE = '',
    INTEGRAL = 'integral',
    DETACHABLE = 'detachable',
    BOTH = 'both',
}

export type DetachableApi = {
    id: number;
    value: DetachableValues;
};

export const DetachableNone: DetachableApi = {
    id: 0,
    value: DetachableValues.NONE,
};

export const DetachableIntegral: DetachableApi = {
    id: 1,
    value: DetachableValues.INTEGRAL,
};

export const DetachableDetachable: DetachableApi = {
    id: 2,
    value: DetachableValues.DETACHABLE,
};

export const DetachableBoth: DetachableApi = {
    id: 3,
    value: DetachableValues.BOTH,
};

export const Detachables = [DetachableNone, DetachableIntegral, DetachableDetachable, DetachableBoth];
// there has got to be a better way of doing this...
export const detachableFromString = (s: string): DetachableApi => {
    switch (s) {
        case DetachableValues.NONE:
            return DetachableNone;
        case DetachableValues.INTEGRAL:
            return DetachableIntegral;
        case DetachableValues.DETACHABLE:
            return DetachableDetachable;
        case DetachableValues.BOTH:
            return DetachableBoth;
        default:
            console.error(`Received invalid value '${s}' for Detachable.`);
            return DetachableNone;
    }
};

export const detachableFromId = (id: null | undefined | number): DetachableApi => {
    if (id == undefined || id == null) return DetachableNone;

    const d = Detachables.find((d) => d.id === id);
    if (d == undefined) {
        throw new Error(`Received invalid id '${id}' for Detachable.`);
    }
    return d;
};

export type HostSimple = {
    id: number;
    name: string;
    aliases: AliasApi[];
    datacomplete: boolean;
    places: PlaceNoTreeApi[];
};

export type GallSimple = {
    id: number;
    name: string;
};

export type HostApi = SpeciesApi & {
    galls: GallSimple[];
    places: PlaceNoTreeApi[];
};
export type GallPropertiesType = {
    alignment: FilterField[];
    cells: FilterField[];
    color: FilterField[];
    form: FilterField[];
    season: FilterField[];
    shape: FilterField[];
    walls: FilterField[];
    texture: FilterField[];
    location: FilterField[];
    detachable: DetachableApi;
    undescribed: boolean;
    hosts: GallHost[];
};

export type GallApi = SpeciesApi &
    GallPropertiesType & {
        gall_id: number;
        excludedPlaces: PlaceNoTreeApi[];
    };

export type TaxSection = TaxonomyEntryNoParent & {
    species: SimpleSpecies[];
};

/**
 *
 */
export type SearchQuery = {
    detachable: DetachableApi[];
    alignment: string[];
    walls: string[];
    locations: string[];
    textures: string[];
    color: string[];
    season: string[];
    shape: string[];
    cells: string[];
    form: string[];
    undescribed: boolean;
    place: string[];
    family: string[];
};

export const EMPTYSEARCHQUERY: SearchQuery = {
    detachable: [DetachableNone],
    alignment: [],
    walls: [],
    locations: [],
    textures: [],
    color: [],
    shape: [],
    cells: [],
    season: [],
    form: [],
    undescribed: false,
    place: [],
    family: [],
};

export type Entry = {
    id: number;
    word: string;
    definition: string;
    urls: string; // /n separated
};
