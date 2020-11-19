/**
 * Types for calling the APIs. These are to be used by browser code when it calls the APIs.
 */

export type Deletable = {
    delete: boolean;
};

export type SpeciesUpsertFields = Deletable & {
    id?: number;
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
