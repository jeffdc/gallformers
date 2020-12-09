/**
 * Types for calling the APIs. These are to be used by browser code when it calls the APIs.
 */
import { abundance, family, location, source, texture } from '@prisma/client';
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

export type SourceApi = {
    id: number;
    title: string;
    author: string;
    pubyear: string;
    link: string;
    citation: string;
};

export type SpeciesSourceApi = {
    id: number;
    species_id: number;
    source_id: number;
    description: Option<string>;
    useasdefault: number;
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

export type SpeciesApi = {
    id: number;
    taxoncode: string;
    name: string;
    synonyms: Option<string>;
    commonnames: Option<string>;
    genus: string;
    abundance: Option<abundance>;
    description: Option<string>; // to make the caller's life easier we will load the default if we can
    family: family;
    speciessource: SpeciesSourceApi[];
};

export type AlignmentApi = {
    id: number;
    alignment: string;
    description: Option<string>;
};

export type CellsApi = {
    id: number;
    cells: string;
    description: Option<string>;
};

export type ColorApi = {
    id: number;
    color: string;
};

export type ShapeApi = {
    id: number;
    shape: string;
    description: Option<string>;
};

export type WallsApi = {
    id: number;
    walls: string;
    description: Option<string>;
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
