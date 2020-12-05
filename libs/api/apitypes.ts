/**
 * Types for calling the APIs. These are to be used by browser code when it calls the APIs.
 */
import {
    abundance,
    alignment,
    cells,
    color,
    family,
    host,
    location,
    shape,
    source,
    species,
    speciessource,
    texture,
    walls,
} from '@prisma/client';

export const GallTaxon = 'gall';
export const HostTaxon = 'plant';

/**
 *
 */
export type SearchQuery = {
    host: string;
    detachable?: string;
    alignment?: string;
    walls?: string;
    locations?: string[];
    textures?: string[];
    color?: string;
    shape?: string;
    cells?: string;
};

export type Deletable = {
    delete?: boolean;
};

export type FamilyApi = family & {
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

export const EmptyFamily = {
    id: -1,
    name: '',
    description: '',
    species: [],
} as FamilyApi;

export type FamilyUpsertFields = {
    name: string;
    description: string;
};

export type SpeciesUpsertFields = Deletable & {
    id?: number;
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

export type Source = speciessource & {
    source: source;
};
export type GallHost = {
    id: number;
    name: string;
};

export type GallLocation = {
    location: location | null;
};
export type GallTexture = {
    texture: texture | null;
};

export type SpeciesApi = species & {
    abundance: abundance | null;
    description: string; // to make the caller's life easier we will load the default
    family: family;
    speciessource: Source[];
};

export type GallApi = SpeciesApi & {
    gall: {
        alignment: alignment | null;
        cells: cells | null;
        color: color | null;
        detachable: number;
        shape: shape | null;
        walls: walls | null;
        galltexture: GallTexture[];
        galllocation: GallLocation[];
    };
    hosts: GallHost[];
};

export type HostSimple = {
    id: number;
    name: string;
    commonnames: string;
    synonyms: string;
};

export type GallSimple = {
    id: number;
    name: string;
};

export type HostGall = host & {
    gallspecies: GallSimple;
};

export type HostApi = species & {
    abundance: abundance | null;
    family: family;
    speciessource: Source[];
    host_galls: HostGall[];
};

export const EmptyHostApi = {
    id: -1,
    name: '',
    genus: '',
    taxoncode: null,
    synonyms: null,
    commonnames: null,
    abundance_id: null,
    abundance: null,
    family_id: -1,
    family: EmptyFamily,
    speciessource: [],
    host_galls: [],
} as HostApi;

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
};

export type GallHostInsertFields = {
    galls: number[];
    hosts: number[];
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
