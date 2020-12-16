import { constFalse, constTrue, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import {
    AlignmentApi,
    CellsApi,
    ColorApi,
    GallApi,
    GallLocation,
    GallTexture,
    SearchQuery,
    ShapeApi,
    WallsApi,
} from '../api/apitypes';

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

/** Make the helper functions available for unit testing. */
export const testables = {
    dontCare: dontCare,
};

const check = <A, B>(a: O.Option<A>, b: O.Option<B>, f: (a: A, b: B) => boolean): boolean =>
    pipe(
        a,
        O.fold(constTrue, (a) =>
            pipe(
                b,
                O.fold(constFalse, (b) => f(a, b)),
            ),
        ),
    );

export const checkGall = (g: GallApi, q: SearchQuery): boolean => {
    const alignment = check(q.alignment, g.gall.alignment, (a: string, b: AlignmentApi) => a === b.alignment);
    const cells = check(q.cells, g.gall.cells, (a: string, b: CellsApi) => a === b.cells);
    const color = check(q.color, g.gall.color, (a: string, b: ColorApi) => a === b.color);
    const detachable = check(q.detachable, g.gall.detachable, (a: string, b: number) => a === (b === 0 ? 'no' : 'yes'));
    const shape = check(q.shape, g.gall.shape, (a: string, b: ShapeApi) => a === b.shape);
    const walls = check(q.walls, g.gall.walls, (a: string, b: WallsApi) => a === b.walls);
    const location = dontCare(q.locations) || (!!g.gall.galllocation && checkLocations(g.gall.galllocation, q.locations));
    const texture = dontCare(q.textures) || (!!g.gall.galltexture && checkTextures(g.gall.galltexture, q.textures));

    return alignment && cells && color && detachable && shape && walls && location && texture;
};
