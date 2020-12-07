import { GallLocation, GallTexture, GallApi, SearchQuery } from '../api/apitypes';

const dontCare = (o: string | string[] | undefined): boolean => {
    const truthy = !!o;
    return !truthy || (truthy && Array.isArray(o) ? o.length === 0 : false);
};

const checkLocations = (gallprops: GallLocation[] | null, queryvals: string[] | undefined): boolean => {
    if (gallprops == null || queryvals == undefined) return false;

    return queryvals.every((q) => gallprops.find((l) => l.location?.location === q));
};

const checkTextures = (gallprops: GallTexture[] | null, queryvals: string[] | undefined): boolean => {
    if (gallprops == null || queryvals == undefined) return false;

    return queryvals.every((q) => gallprops.find((l) => l.texture?.texture === q));
};

/** Make the helper functions available for unit testing. */
export const testables = {
    dontCare: dontCare,
};

export const checkGall = (g: GallApi, q: SearchQuery): boolean => {
    const alignment = dontCare(q.alignment) || (!!g.gall?.alignment && g.gall?.alignment?.alignment === q.alignment);
    const cells = dontCare(q.cells) || (!!g.gall?.cells && g.gall?.cells?.cells === q.cells);
    const color = dontCare(q.color) || (!!g.gall?.color && g.gall?.color?.color === q.color);
    const detachable = dontCare(q.detachable) || (g.gall.detachable === 0 ? 'no' : 'yes') === q.detachable;
    const shape = dontCare(q.shape) || (!!g.gall?.shape && g.gall?.shape?.shape === q.shape);
    const walls = dontCare(q.walls) || (!!g.gall?.walls && g.gall?.walls?.walls === q.walls);
    const location = dontCare(q.locations) || (!!g.gall.galllocation && checkLocations(g.gall.galllocation, q.locations));
    const texture = dontCare(q.textures) || (!!g.gall.galltexture && checkTextures(g.gall.galltexture, q.textures));

    // console.log(`a:${alignment} ce:${cells} co:${color} d:${detachable} s: ${shape} w:${walls} l:${location} t:${texture}`);
    return alignment && cells && color && detachable && shape && walls && location && texture;
};
