/**
 * Types for calling the APIs. These are to be used by browser code when it calls the APIs so all database stuff
 * must stay out of here.
 */
import { alias } from '@prisma/client';
import * as O from 'fp-ts/lib/Option';
import { Option } from 'fp-ts/lib/Option';
import { FGS } from './taxonomy';

export const GallTaxon = 'gall';
export const HostTaxon = 'plant';

export type DetachableApi = {
    id: number;
    value: DetachableValues;
};

export const DetachableNone: DetachableApi = {
    id: 0,
    value: '',
};

export const DetachableIntegral: DetachableApi = {
    id: 1,
    value: 'integral',
};

export const DetachableDetachable: DetachableApi = {
    id: 2,
    value: 'detachable',
};

export const DetachableBoth: DetachableApi = {
    id: 3,
    value: 'both',
};

export const Detachables = [DetachableNone, DetachableIntegral, DetachableDetachable, DetachableBoth];
export type DetachableValues = '' | 'integral' | 'detachable' | 'both';

// there has got to be a better way of doing this...
export const detachableFromString = (s: string): DetachableApi => {
    switch (s) {
        case '':
            return DetachableNone;
        case 'integral':
            return DetachableIntegral;
        case 'detachable':
            return DetachableDetachable;
        case 'both':
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
    detachable: DetachableValues;
    undescribed: boolean;
};

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

export type SourceWithSpeciesApi = SourceApi & {
    species: SimpleSpecies[];
};

export type SourceWithSpeciesSourceApi = SourceApi & {
    speciessource: Omit<SpeciesSourceApi, 'source'>[];
};

export type SpeciesSourceApi = {
    id: number;
    species_id: number;
    source_id: number;
    description: string;
    useasdefault: number;
    externallink: string;
    source: SourceApi;
};

export type GallHost = {
    id: number;
    name: string;
};

export type AbundanceApi = {
    id: number;
    abundance: string;
    description: string;
    reference: Option<string>;
};
export const EmptyAbundance: AbundanceApi = {
    id: -1,
    abundance: '',
    description: '',
    reference: O.none,
};

export type SimpleSpecies = {
    id: number;
    taxoncode: string;
    name: string;
};
export type WithImages = {
    images: ImageApi[] | ImageNoSourceApi[];
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

export type FilterFieldWithType = FilterField & {
    fieldType: FilterFieldType;
};

// For now only these two until we support the Place hierarchy.
export const PLACE_TYPES = ['state', 'province'];

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

export type GallApi = SpeciesApi & {
    gall: {
        id: number;
        gallalignment: FilterField[];
        gallcells: FilterField[];
        gallcolor: FilterField[];
        gallseason: FilterField[];
        detachable: DetachableApi;
        gallshape: FilterField[];
        gallwalls: FilterField[];
        galltexture: FilterField[];
        galllocation: FilterField[];
        gallform: FilterField[];
        undescribed: boolean;
    };
    hosts: GallHost[];
};

export type HostSimple = {
    id: number;
    name: string;
    aliases: alias[];
    datacomplete: boolean;
};

export type GallSimple = {
    id: number;
    name: string;
};

export type HostApi = SpeciesApi & {
    galls: GallSimple[];
    places: PlaceNoTreeApi[];
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
    genus: string;
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

export const NONE = '';
export const CC0 = 'Public Domain / CC0';
export const CCBY = 'CC-BY';
export const ALLRIGHTS = 'All Rights Reserved';

export type LicenseType = typeof NONE | typeof CC0 | typeof CCBY | typeof ALLRIGHTS;

export const asLicenseType = (l: string): LicenseType => {
    // Seems like there should be a better way to handle this and maintain types.
    switch (l) {
        case NONE:
            return NONE;
        case CC0:
            return CC0;
        case CCBY:
            return CCBY;
        case ALLRIGHTS:
            return ALLRIGHTS;
        default:
            throw new Error(`Invalid license type: '${l}'.`);
    }
};

export type ImageNoSourceApi = {
    id: number;
    attribution: string;
    creator: string;
    path: string;
    uploader: string;
    lastchangedby: string;
    caption: string;
    speciesid: number;
    default: boolean;
    small: string;
    medium: string;
    large: string;
    xlarge: string;
    original: string;
};

export type ImageApi = ImageNoSourceApi & {
    license: LicenseType;
    licenselink: string;
    sourcelink: string;
    source: Option<SourceWithSpeciesSourceApi>;
};

export type ImagePaths = {
    small: string[];
    medium: string[];
    large: string[];
    xlarge: string[];
    original: string[];
};
