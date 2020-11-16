/**
 * Types for calling the APIs. These are to be used by browser code when it calls the APIs.
 */

export type SpeciesUpsertFields = {
    name: string;
    commonnames: string;
    synonyms: string;
    family: string;
    abundance: string;
    description: string;
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

export type SourceUpsertFields = {
    title: string;
    author: string;
    pubyear: string;
    link: string;
    citation: string;
};

export type SpeciesSourceInsertFields = {
    species: number[];
    sources: number[];
};

export type HostInsertFields = {
    galls: number[];
    hosts: number[];
};

export type FamilyUpsertFields = {
    name: string;
    description: string;
};
