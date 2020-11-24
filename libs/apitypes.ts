/**
 * Types for calling the APIs. These are to be used by browser code when it calls the APIs.
 */

import {
    abundance,
    alignment,
    cells,
    color,
    family,
    gall,
    host,
    location,
    shape,
    source,
    species,
    speciessource,
    texture,
    walls,
} from '@prisma/client';

export type Deletable = {
    delete?: boolean;
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

export type GallRes = {
    id: number;
    species_id: number;
    taxoncode: string;
    detachable: number | undefined;
    alignment_id: number | undefined;
    walls_id: number | undefined;
    cells_id: number | undefined;
    color_id: number | undefined;
    shape_id: number | undefined;
    locations: (number | null)[] | undefined;
    textures: (number | null)[] | undefined;
    hosts: (number | null)[] | undefined;
};

export type Source = speciessource & {
    source: source;
};
export type GallHost = host & {
    hostspecies: species | null;
};
export type GallSpecies = species & {
    abundance: abundance | null;
    family: family;
    hosts: GallHost[];
    speciessource: Source[];
};
export type GallLocation = {
    location: location | null;
};
export type GallTexture = {
    texture: texture | null;
};

export type GallApi =
    | (gall & {
          alignment: alignment | null;
          cells: cells | null;
          color: color | null;
          shape: shape | null;
          walls: walls | null;
          galltexture: GallTexture[];
          galllocation: GallLocation[];
          species: GallSpecies;
      })
    | null;

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

export type HostApi =
    | (species & {
          abundance: abundance | null;
          family: family;
          speciessource: Source[];
          host_galls: HostGall[];
      })
    | null;

export type SourceUpsertFields = {
    title: string;
    author: string;
    pubyear: string;
    link: string;
    citation: string;
};

export type SpeciesSourceInsertFields = {
    species: number;
    source: number;
    description: string;
    useasdefault: boolean;
};

export type HostInsertFields = {
    galls: number[];
    hosts: number[];
};

export type FamilyUpsertFields = {
    name: string;
    description: string;
};

export type DeleteResults = {
    name: string;
};

export type GlossaryEntryUpsertFields = Deletable & {
    word: string;
    definition: string;
    urls: string; // newline separated
};
