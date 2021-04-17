import { DetachableApi, DetachableBoth, DetachableNone, GallApi, GallLocation, GallTexture, SearchQuery } from '../api/apitypes';

const dontCare = (o: string | string[] | undefined): boolean => {
    const truthy = !!o;
    return !truthy || (truthy && Array.isArray(o) ? o.length === 0 : false);
};

const checkLocations = (locs: GallLocation[], queryvals: string[] | undefined): boolean => {
    if (queryvals == undefined) return false;

    return queryvals.every((q) => locs.find((l) => l.loc === q));
};

const checkTextures = (textures: GallTexture[], queryvals: string[] | undefined): boolean => {
    if (queryvals == undefined) return false;

    return queryvals.every((q) => textures.find((l) => l.tex === q));
};

const checkArray = <T>(ts: T[], pred: (t: T, s: string) => boolean, queryvals: string[] | undefined): boolean => {
    if (queryvals == undefined) return false;

    return queryvals.every((q) => ts.find((t) => pred(t, q)));
};

/** Make the helper functions available for unit testing. */
export const testables = {
    dontCare: dontCare,
};

const checkDetachable = (g: DetachableApi, q: DetachableApi): boolean => {
    // query of None matches all
    if (q.value === DetachableNone.value) return true;

    // query of Both matches everything but None
    if (q.value === DetachableBoth.value && g.value !== DetachableNone.value) return true;

    // otherwise must match including matches on Both
    return q.value === g.value || g.value === DetachableBoth.value;
};

export const checkGall = (g: GallApi, q: SearchQuery): boolean => {
    const alignment =
        dontCare(q.alignment) ||
        (!!g.gall.gallalignment && checkArray(g.gall.gallalignment, (a, b) => a.alignment === b, q.alignment));
    const cells = dontCare(q.cells) || (!!g.gall.gallcells && checkArray(g.gall.gallcells, (a, b) => a.cells === b, q.cells));
    const color = dontCare(q.color) || (!!g.gall.gallcolor && checkArray(g.gall.gallcolor, (a, b) => a.color === b, q.color));
    const detachable = checkDetachable(g.gall.detachable, q.detachable[0]);
    const shape = dontCare(q.shape) || (!!g.gall.gallshape && checkArray(g.gall.gallshape, (a, b) => a.shape === b, q.shape));
    const walls = dontCare(q.walls) || (!!g.gall.gallwalls && checkArray(g.gall.gallwalls, (a, b) => a.walls === b, q.walls));
    const location = dontCare(q.locations) || (!!g.gall.galllocation && checkLocations(g.gall.galllocation, q.locations));
    const texture = dontCare(q.textures) || (!!g.gall.galltexture && checkTextures(g.gall.galltexture, q.textures));

    return alignment && cells && color && detachable && shape && walls && location && texture;
};
