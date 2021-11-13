import { DetachableApi, DetachableBoth, DetachableNone, GallIDApi, SearchQuery } from '../api/apitypes';

const dontCare = (o: string | string[] | undefined): boolean => {
    const truthy = !!o;
    return !truthy || (truthy && Array.isArray(o) ? o.length === 0 : false);
};

const checkArray = (ts: string[], queryvals: string[] | undefined): boolean => {
    if (queryvals == undefined) return false;

    return queryvals.every((q) => ts.find((t) => t === q));
};

/** Make the helper functions available for unit testing. */
export const testables = {
    dontCare: dontCare,
};

const checkDetachable = (g: DetachableApi, q: DetachableApi): boolean => {
    // query of None matches all
    if (q.value === DetachableNone.value) return true;

    // query of Both matches only those with literal Both
    if (q.value === DetachableBoth.value && g.value === DetachableBoth.value) return true;

    // otherwise must match including matches on Both
    return q.value === g.value || g.value === DetachableBoth.value;
};

export const LEAF_ANYWHERE = 'leaf (anywhere)';
export const GALL_FORM = 'gall';
export const NONGALL_FORM = 'non-gall';

export const checkGall = (g: GallIDApi, q: SearchQuery): boolean => {
    const alignment = dontCare(q.alignment) || (!!g.alignments && checkArray(g.alignments, q.alignment));
    const cells = dontCare(q.cells) || (!!g.cells && checkArray(g.cells, q.cells));
    const color = dontCare(q.color) || (!!g.colors && checkArray(g.colors, q.color));
    const season = dontCare(q.season) || (!!g.seasons && checkArray(g.seasons, q.season));
    const detachable = checkDetachable(g.detachable, q.detachable[0]);
    const shape = dontCare(q.shape) || (!!g.shapes && checkArray(g.shapes, q.shape));
    const walls = dontCare(q.walls) || (!!g.walls && checkArray(g.walls, q.walls));
    let location = false;
    if (q.locations.find((l) => l === LEAF_ANYWHERE)) {
        location = g.locations.some((l) => l.includes('leaf'));
        const locs = q.locations.filter((l) => l !== LEAF_ANYWHERE);
        location = location && (dontCare(locs) || (!!g.locations && checkArray(g.locations, locs)));
    } else {
        location = dontCare(q.locations) || (!!g.locations && checkArray(g.locations, q.locations));
    }
    const texture = dontCare(q.textures) || (!!g.textures && checkArray(g.textures, q.textures));
    let form = false;
    if (q.form.find((f) => f === GALL_FORM)) {
        const forms = q.form.filter((f) => f !== GALL_FORM);
        // gall selected as a form, which means not not_gall form
        form = !g.forms.find((f) => f === NONGALL_FORM);
        form = form && (dontCare(forms) || (!!g.forms && checkArray(g.forms, forms)));
    } else {
        // gall not selected as a form so we can just do the usual check
        form = dontCare(q.form) || (!!g.forms && checkArray(g.forms, q.form));
    }
    const undescribed = !q.undescribed || g.undescribed;
    const place = dontCare(q.place) || (!!g.places && checkArray(g.places, q.place));
    const family = dontCare(q.family) || (!!g.family && checkArray([g.family], q.family));

    return (
        alignment &&
        cells &&
        color &&
        season &&
        detachable &&
        shape &&
        walls &&
        location &&
        texture &&
        form &&
        undescribed &&
        place &&
        family
    );
};
