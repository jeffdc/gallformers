import { GallIDApi, SearchQuery } from '../../../libs/api/apitypes';
import {
    DetachableApi,
    DetachableBoth,
    DetachableDetachable,
    DetachableIntegral,
    DetachableNone,
} from '../../../libs/api/apitypes';
import { checkGall, testables } from '../../../libs/utils/gallsearch';

const { dontCare } = testables;

describe('dontCare tests', () => {
    test('Should return true for undefined, empty string, or empty array', () => {
        expect(dontCare(undefined)).toBeTruthy();
        expect(dontCare('')).toBeTruthy();
        expect(dontCare([])).toBeTruthy();
    });
});

describe('checkGall tests', () => {
    const g: GallIDApi = {
        id: -1,
        undescribed: false,
        alignments: [],
        cells: [],
        colors: [],
        detachable: DetachableNone,
        locations: [],
        seasons: [],
        textures: [],
        shapes: [],
        walls: [],
        forms: [],
        name: 'Gallus gallus',
        images: [],
        datacomplete: false,
        places: [],
        family: '',
    };

    const q: SearchQuery = {
        alignment: [],
        cells: [],
        color: [],
        detachable: [DetachableNone],
        locations: [],
        season: [],
        shape: [],
        textures: [],
        walls: [],
        form: [],
        undescribed: false,
        place: [],
        family: [''],
    };

    // helper to create test galls in the tests.
    const makeG = (k: keyof GallIDApi, v: string[] | DetachableApi): GallIDApi => ({
        ...g,
        [k]: v,
    });

    test('Should not fail to match for any search field that is undefined, empty string, or empty array', () => {
        expect(checkGall(g, q)).toBeTruthy();
        expect(checkGall(makeG('alignments', ['']), q)).toBeTruthy();
        expect(checkGall(makeG('cells', ['']), q)).toBeTruthy();
        expect(checkGall(makeG('colors', ['']), q)).toBeTruthy();
        expect(checkGall(makeG('seasons', ['']), q)).toBeTruthy();
        expect(checkGall(makeG('shapes', ['']), q)).toBeTruthy();
        expect(checkGall(makeG('walls', ['']), q)).toBeTruthy();
        expect(checkGall(makeG('locations', ['']), q)).toBeTruthy();
        expect(checkGall(makeG('textures', ['']), q)).toBeTruthy();
        expect(checkGall(makeG('places', ['']), q)).toBeTruthy();
    });

    test('Should match when provided query has single matches', () => {
        expect(
            checkGall(makeG('alignments', ['foo']), {
                ...q,
                alignment: ['foo'],
            }),
        ).toBeTruthy();
        expect(
            checkGall(makeG('cells', ['foo']), {
                ...q,
                cells: ['foo'],
            }),
        ).toBeTruthy();
        expect(
            checkGall(makeG('colors', ['foo']), {
                ...q,
                color: ['foo'],
            }),
        ).toBeTruthy();
        expect(
            checkGall(makeG('seasons', ['foo']), {
                ...q,
                season: ['foo'],
            }),
        ).toBeTruthy();
        expect(
            checkGall(makeG('shapes', ['foo']), {
                ...q,
                shape: ['foo'],
            }),
        ).toBeTruthy();
        expect(
            checkGall(makeG('walls', ['foo']), {
                ...q,
                walls: ['foo'],
            }),
        ).toBeTruthy();
        expect(
            checkGall(makeG('locations', ['foo']), {
                ...q,
                locations: ['foo'],
            }),
        ).toBeTruthy();
        expect(
            checkGall(makeG('textures', ['foo']), {
                ...q,
                textures: ['foo'],
            }),
        ).toBeTruthy();
        expect(
            checkGall(makeG('places', ['foo']), {
                ...q,
                place: ['foo'],
            }),
        ).toBeTruthy();
    });

    test('Should handle all cases for detachable', () => {
        const conditions = [
            // 4 None cases all should match
            { a: DetachableDetachable, b: DetachableNone, expected: true },
            { a: DetachableIntegral, b: DetachableNone, expected: true },
            { a: DetachableBoth, b: DetachableNone, expected: true },
            { a: DetachableNone, b: DetachableNone, expected: true },
            // 3 Both cases one match two not
            { a: DetachableBoth, b: DetachableBoth, expected: true },
            { a: DetachableDetachable, b: DetachableBoth, expected: false },
            { a: DetachableIntegral, b: DetachableBoth, expected: false },
            // 3 Detachable cases two match one not
            { a: DetachableDetachable, b: DetachableDetachable, expected: true },
            { a: DetachableBoth, b: DetachableDetachable, expected: true },
            { a: DetachableIntegral, b: DetachableDetachable, expected: false },
            // 3 Integral cases two match one not
            { a: DetachableIntegral, b: DetachableIntegral, expected: true },
            { a: DetachableBoth, b: DetachableIntegral, expected: true },
            { a: DetachableDetachable, b: DetachableIntegral, expected: false },
        ];

        conditions.forEach(({ a, b, expected }) => {
            expect(
                checkGall(makeG('detachable', a), {
                    ...q,
                    detachable: [b],
                }),
            ).toBe(expected);
        });
    });

    test('Should match when provided query has multiple matches', () => {
        expect(
            checkGall(
                {
                    ...g,
                    alignments: ['afoo'],
                    colors: ['cofoo'],
                    cells: ['cefoo'],
                    seasons: ['sefoo'],
                    shapes: ['sfoo'],
                    walls: ['wfoo'],
                    locations: ['lfoo'],
                    textures: ['tfoo'],
                    places: ['pfoo'],
                },
                {
                    ...q,
                    alignment: ['afoo'],
                    color: ['cofoo'],
                    cells: ['cefoo'],
                    season: ['sefoo'],
                    shape: ['sfoo'],
                    walls: ['wfoo'],
                    locations: ['lfoo'],
                    textures: ['tfoo'],
                    place: ['pfoo'],
                },
            ),
        ).toBeTruthy();
    });

    test('Handles array types correctly', () => {
        const theG = {
            ...g,
            alignments: ['afoo1', 'afoo2'],
            colors: ['cfoo1', 'cfoo2'],
            seasons: ['sefoo1', 'sefoo2'],
            cells: ['cefoo1', 'cefoo2'],
            walls: ['wfoo1', 'wfoo2'],
            shapes: ['sfoo1', 'sfoo2'],
            locations: ['lfoo1', 'lfoo2'],
            textures: ['tfoo'],
        };

        expect(
            checkGall(theG, {
                ...q,
                locations: ['lfoo'],
                textures: ['tfoo'],
            }),
        ).toBeFalsy();

        expect(
            checkGall(theG, {
                ...q,
                alignment: ['afoo1'],
                color: ['cfoo1'],
                season: ['sefoo1'],
                cells: ['cefoo1'],
                walls: ['wfoo1'],
                shape: ['sfoo1'],
                locations: ['lfoo1'],
                textures: ['tfoo'],
            }),
        ).toBeTruthy();

        expect(
            checkGall(theG, {
                ...q,
                walls: ['wfoo1', 'wfoo2'],
                locations: ['lfoo1', 'lfoo2'],
                textures: ['tfoo'],
            }),
        ).toBeTruthy();

        expect(
            checkGall(theG, {
                ...q,
                locations: ['lfoo1', 'lfoo2', 'nope'],
                textures: ['tfoo'],
            }),
        ).toBeFalsy();

        expect(
            checkGall(theG, {
                ...q,
                alignment: [],
                color: [],
                cells: [],
                season: [],
                walls: [],
                shape: [],
                locations: [],
                textures: [],
            }),
        ).toBeTruthy();
    });
});
