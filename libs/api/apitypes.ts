/**
 * Types for calling the APIs. These are to be used by browser code when it calls the APIs so all database stuff
 * must stay out of here.
 */
import { alias } from '@prisma/client';
import * as O from 'fp-ts/lib/Option';
import { Option } from 'fp-ts/lib/Option';
import { ParsedUrlQuery } from 'querystring';
import { FGS, TaxonomyEntry } from './taxonomy';

export const GallTaxon = 'gall';
export const HostTaxon = 'plant';

/**
 *
 * @param q
 */
export const toSearchQuery = (q: ParsedUrlQuery): SearchQuery => {
    if (!q.host) throw new Error('Received query without host!');

    return {
        alignment: q.alignment == undefined ? [] : [q.alignment].flat(),
        cells: q.cells == undefined ? [] : [q.cells].flat(),
        color: q.color == undefined ? [] : [q.color].flat(),
        detachable: q.detachable == undefined ? DetachableNone : detachableFromString(q.detachable.toString()),
        host: q.host.toString(),
        locations: q.locations == undefined ? [] : [q.locations].flat(),
        shape: q.shape == undefined ? [] : [q.shape].flat(),
        textures: q.textures == undefined ? [] : [q.textures].flat(),
        walls: q.walls == undefined ? [] : [q.walls].flat(),
    };
};

export const emptySearchQuery = (): SearchQuery => ({
    host: '',
    detachable: DetachableNone,
    alignment: [],
    walls: [],
    locations: [],
    textures: [],
    color: [],
    shape: [],
    cells: [],
});

/**
 *
 */
export type SearchQuery = {
    host: string;
    detachable: DetachableApi;
    alignment: string[];
    walls: string[];
    locations: string[];
    textures: string[];
    color: string[];
    shape: string[];
    cells: string[];
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

export type SpeciesUpsertFields = {
    id: number;
    name: string;
    datacomplete: boolean;
    aliases: AliasApi[];
    abundance: string | null | undefined;
    fgs: FGS;
};

export type GallUpsertFields = SpeciesUpsertFields & {
    gallid: number; // if less than 0 then new
    hosts: number[];
    locations: number[];
    colors: number[];
    shapes: number[];
    textures: number[];
    alignments: number[];
    walls: number[];
    cells: number[];
    detachable: DetachableValues;
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
};

export type SpeciesApi = SimpleSpecies & {
    datacomplete: boolean;
    abundance: Option<AbundanceApi>;
    description: Option<string>; // to make the caller's life easier we will load the default if we can
    speciessource: SpeciesSourceApi[];
    images: ImageApi[];
    aliases: AliasApi[];
};

export type AliasApi = {
    id: number;
    name: string;
    type: string;
    description: string;
};

export const EmptyAlias: AliasApi = {
    id: -1,
    name: '',
    type: 'common',
    description: '',
};

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
        id: number;
        gallalignment: AlignmentApi[];
        gallcells: CellsApi[];
        gallcolor: ColorApi[];
        detachable: DetachableApi;
        gallshape: ShapeApi[];
        gallwalls: WallsApi[];
        galltexture: GallTexture[];
        galllocation: GallLocation[];
    };
    hosts: GallHost[];
};

export type HostSimple = {
    id: number;
    name: string;
    aliases: alias[];
};

export type GallSimple = {
    id: number;
    name: string;
};

export type HostApi = SpeciesApi & {
    galls: GallSimple[];
};

export type SourceUpsertFields = Deletable & {
    id: number;
    title: string;
    author: string;
    pubyear: string;
    link: string;
    citation: string;
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
    xlarge: string;
    original: string;
};

export type ImagePaths = {
    small: string[];
    medium: string[];
    large: string[];
    xlarge: string[];
    original: string[];
};
