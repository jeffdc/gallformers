/**
 * Types for calling the APIs. These are to be used by browser code when it calls the APIs.
 */
import * as O from 'fp-ts/lib/Option';
import { Option } from 'fp-ts/lib/Option';
import { ParsedUrlQuery } from 'querystring';

export const GallTaxon = 'gall';
export const HostTaxon = 'plant';

/**
 *
 * @param q
 */
export const toSearchQuery = (q: ParsedUrlQuery): SearchQuery => {
    if (!q.host) throw new Error('Received query without host!');

    return {
        alignment: O.fromNullable(q.alignment?.toString()),
        cells: O.fromNullable(q.cells?.toString()),
        color: O.fromNullable(q.color?.toString()),
        detachable: O.fromNullable(q.detachable?.toString()),
        host: q.host.toString(),
        locations: q.locations == undefined ? [] : [q.locations].flat(),
        shape: O.fromNullable(q.shape?.toString()),
        textures: q.textures == undefined ? [] : [q.textures].flat(),
        walls: O.fromNullable(q.walls?.toString()),
    };
};

export const emptySearchQuery = (): SearchQuery => ({
    host: '',
    detachable: O.none,
    alignment: O.none,
    walls: O.none,
    locations: [],
    textures: [],
    color: O.none,
    shape: O.none,
    cells: O.none,
});

/**
 *
 */
export type SearchQuery = {
    host: string;
    detachable: Option<string>;
    alignment: Option<string>;
    walls: Option<string>;
    locations: string[];
    textures: string[];
    color: Option<string>;
    shape: Option<string>;
    cells: Option<string>;
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
    'Psyllid',
    'Sawfly',
    'Scale',
    'Thrips',
    'True Bug',
    'Wasp',
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
    'Plant',
    'Psyllid',
    'Sawfly',
    'Scale',
    'Thrips',
    'True Bug',
    'Wasp',
] as const;
export type FamilyTypesTuple = typeof ALL_FAMILY_TYPES;
export type FamilyType = FamilyTypesTuple[number];
export type FamilyGallTypesTuples = typeof GALL_FAMILY_TYPES;
export type FamilyGallType = FamilyGallTypesTuples[number];
export type FamilyHostTypesTuple = typeof HOST_FAMILY_TYPES;
export type FamilyHostType = FamilyHostTypesTuple[number];

export type FamilyApi = {
    id: number;
    name: string;
    description: string;
};
export const EmptyFamily: FamilyApi = { id: -1, name: '', description: '' };

export type FamilyWithSpecies = FamilyApi & {
    species: {
        id: number;
        name: string;
        gall: {
            species: {
                id: number;
                name: string;
            } | null;
        } | null;
    }[];
};

export type FamilyUpsertFields = {
    name: string;
    description: string;
};

export type SpeciesUpsertFields = {
    id: number;
    name: string;
    commonnames: string;
    synonyms: string;
    family: string;
    abundance: string;
};

export type GallUpsertFields = SpeciesUpsertFields & {
    hosts: number[];
    locations: number[];
    color: string;
    shape: string;
    textures: number[];
    alignment: string;
    walls: string;
    cells: string;
    detachable: string;
};

export type SourceApi = {
    id: number;
    title: string;
    author: string;
    pubyear: string;
    link: string;
    citation: string;
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

export type GallLocation = {
    id: number;
    loc: string;
    description: Option<string>;
};

export type GallTexture = {
    id: number;
    tex: string;
    description: Option<string>;
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
    genus: string;
};

export type SpeciesApi = SimpleSpecies & {
    synonyms: Option<string>;
    commonnames: Option<string>;
    abundance: Option<AbundanceApi>;
    description: Option<string>; // to make the caller's life easier we will load the default if we can
    family: FamilyApi;
    speciessource: SpeciesSourceApi[];
    images: ImageApi[];
};

export type AlignmentApi = {
    id: number;
    alignment: string;
    description: Option<string>;
};
export const EmptyAlignment: AlignmentApi = {
    id: -1,
    alignment: '',
    description: O.none,
};

export type CellsApi = {
    id: number;
    cells: string;
    description: Option<string>;
};
export const EmptyCells: CellsApi = {
    id: -1,
    cells: '',
    description: O.none,
};

export type ColorApi = {
    id: number;
    color: string;
};
export const EmptyColor: ColorApi = {
    id: -1,
    color: '',
};

export type ShapeApi = {
    id: number;
    shape: string;
    description: Option<string>;
};
export const EmptyShape: ShapeApi = {
    id: -1,
    shape: '',
    description: O.none,
};

export type WallsApi = {
    id: number;
    walls: string;
    description: Option<string>;
};
export const EmptyWalls: WallsApi = {
    id: -1,
    walls: '',
    description: O.none,
};

export type GallApi = SpeciesApi & {
    gall: {
        alignment: Option<AlignmentApi>;
        cells: Option<CellsApi>;
        color: Option<ColorApi>;
        detachable: Option<number>;
        shape: Option<ShapeApi>;
        walls: Option<WallsApi>;
        galltexture: GallTexture[];
        galllocation: GallLocation[];
    };
    hosts: GallHost[];
};

export type HostSimple = {
    id: number;
    name: string;
    commonnames: Option<string>;
    synonyms: Option<string>;
};

export type GallSimple = {
    id: number;
    name: string;
};

export type HostApi = SpeciesApi & {
    galls: GallSimple[];
};

export type SourceUpsertFields = Deletable & {
    title: string;
    author: string;
    pubyear: string;
    link: string;
    citation: string;
};

export type SpeciesSourceInsertFields = Deletable & {
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

export type ImageApi = {
    id: number;
    attribution: string;
    creator: string;
    license: LicenseType;
    licenselink: string;
    path: string;
    sourcelink: string;
    source: Option<SourceWithSpeciesSourceApi>;
    uploader: string;
    lastchangedby: string;
    speciesid: number;
    default: boolean;
    small: string;
    medium: string;
    large: string;
    original: string;
};

export type ImagePaths = {
    small: string[];
    medium: string[];
    large: string[];
    original: string[];
};
