import {
    alignment,
    cells,
    color,
    gall,
    galllocation,
    galltexture,
    location,
    shape,
    species,
    texture,
    walls,
} from '@prisma/client';

export type GallLocation = galllocation & {
    location: location | null;
};

export type GallTexture = galltexture & {
    texture: texture | null;
};

export type Gall = gall & {
    alignment: alignment | null;
    cells: cells | null;
    color: color | null;
    galllocation: GallLocation[];
    shape: shape | null;
    species: species | null;
    galltexture: GallTexture[];
    walls: walls | null;
};

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
