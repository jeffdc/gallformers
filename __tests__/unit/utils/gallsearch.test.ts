import * as O from 'fp-ts/lib/Option';
import {
    AlignmentApi,
    CellsApi,
    ColorApi,
    DetachableApi,
    DetachableBoth,
    DetachableDetachable,
    DetachableIntegral,
    DetachableNone,
    GallApi,
    GallLocation,
    GallTaxon,
    GallTexture,
    SearchQuery,
    ShapeApi,
    WallsApi,
} from '../../../libs/api/apitypes';
import { FAMILY, GENUS } from '../../../libs/api/taxonomy';
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
    const g: GallApi = {
        abundance: O.none,
        description: O.of('The chicken gall...'),
        gall: {
            id: -1,
            undescribed: false,
            gallalignment: [],
            gallcells: [],
            gallcolor: [],
            detachable: DetachableNone,
            galllocation: [],
            galltexture: [],
            gallshape: [],
            gallwalls: [],
        },
        hosts: [],
        id: 1,
        name: 'Gallus gallus',
        speciessource: [],
        taxoncode: GallTaxon,
        images: [],
        datacomplete: false,
        aliases: [],
        fgs: {
            family: { id: 1, name: 'Phasianidae', description: '', type: FAMILY },
            genus: { id: 1, name: 'Gallus', description: '', type: GENUS },
            section: O.none,
        },
    };

    const q: SearchQuery = {
        alignment: [],
        cells: [],
        color: [],
        detachable: [DetachableNone],
        locations: [],
        shape: [],
        textures: [],
        walls: [],
    };

    // helper to create test galls in the tests.
    const makeG = (
        k: keyof GallApi['gall'],
        v: AlignmentApi[] | CellsApi[] | ColorApi[] | DetachableApi | GallLocation[] | GallTexture[] | ShapeApi[] | WallsApi[],
    ): GallApi => ({
        ...g,
        gall: { ...g.gall, [k]: v },
    });

    test('Should not fail to match for any search field that is undefined, empty string, or empty array', () => {
        expect(checkGall(g, q)).toBeTruthy();
        expect(checkGall(makeG('gallalignment', [{ alignment: '', id: 1, description: O.of('') }]), q)).toBeTruthy();
        expect(checkGall(makeG('gallcells', [{ cells: '', id: 1, description: O.of('') }]), q)).toBeTruthy();
        expect(checkGall(makeG('gallcolor', [{ color: '', id: 1 }]), q)).toBeTruthy();
        expect(checkGall(makeG('gallshape', [{ shape: '', id: 1, description: O.of('') }]), q)).toBeTruthy();
        expect(checkGall(makeG('gallwalls', [{ walls: '', id: 1, description: O.of('') }]), q)).toBeTruthy();
        expect(checkGall(makeG('galllocation', [{ loc: '', id: 1, description: O.of('') }]), q)).toBeTruthy();
        expect(checkGall(makeG('galltexture', [{ tex: '', id: 1, description: O.of('') }]), q)).toBeTruthy();
    });

    test('Should match when provided query has single matches', () => {
        expect(
            checkGall(makeG('gallalignment', [{ alignment: 'foo', id: 1, description: O.of('') }]), {
                ...q,
                alignment: ['foo'],
            }),
        ).toBeTruthy();
        expect(
            checkGall(makeG('gallcells', [{ cells: 'foo', id: 1, description: O.of('') }]), {
                ...q,
                cells: ['foo'],
            }),
        ).toBeTruthy();
        expect(
            checkGall(makeG('gallcolor', [{ color: 'foo', id: 1 }]), {
                ...q,
                color: ['foo'],
            }),
        ).toBeTruthy();
        expect(
            checkGall(makeG('gallshape', [{ shape: 'foo', id: 1, description: O.of('') }]), {
                ...q,
                shape: ['foo'],
            }),
        ).toBeTruthy();
        expect(
            checkGall(makeG('gallwalls', [{ walls: 'foo', id: 1, description: O.of('') }]), {
                ...q,
                walls: ['foo'],
            }),
        ).toBeTruthy();
        expect(
            checkGall(makeG('galllocation', [{ loc: 'foo', id: 1, description: O.of('') }]), {
                ...q,
                locations: ['foo'],
            }),
        ).toBeTruthy();
        expect(
            checkGall(makeG('galltexture', [{ tex: 'foo', id: 1, description: O.of('') }]), {
                ...q,
                textures: ['foo'],
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
            // 3 Both cases all should match
            { a: DetachableBoth, b: DetachableBoth, expected: true },
            { a: DetachableDetachable, b: DetachableBoth, expected: true },
            { a: DetachableIntegral, b: DetachableBoth, expected: true },
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
                    gall: {
                        ...g.gall,
                        gallalignment: [{ alignment: 'afoo', id: 1, description: O.none }],
                        gallcolor: [{ color: 'cofoo', id: 1 }],
                        gallcells: [{ cells: 'cefoo', id: 1, description: O.none }],
                        gallshape: [{ shape: 'sfoo', id: 1, description: O.none }],
                        gallwalls: [{ walls: 'wfoo', id: 1, description: O.none }],
                        galllocation: [{ loc: 'lfoo', id: 1, description: O.none }],
                        galltexture: [{ tex: 'tfoo', id: 1, description: O.none }],
                    },
                },
                {
                    ...q,
                    alignment: ['afoo'],
                    color: ['cofoo'],
                    cells: ['cefoo'],
                    shape: ['sfoo'],
                    walls: ['wfoo'],
                    locations: ['lfoo'],
                    textures: ['tfoo'],
                },
            ),
        ).toBeTruthy();
    });

    test('Handles array types correctly', () => {
        const theG = {
            ...g,
            gall: {
                ...g.gall,
                gallalignment: [
                    { alignment: 'afoo1', id: 1, description: O.of('') },
                    { alignment: 'afoo2', id: 2, description: O.of('') },
                ],
                gallcolor: [
                    { color: 'cfoo1', id: 1, description: O.of('') },
                    { color: 'cfoo2', id: 2, description: O.of('') },
                ],
                gallcells: [
                    { cells: 'cefoo1', id: 1, description: O.of('') },
                    { cells: 'cefoo2', id: 2, description: O.of('') },
                ],
                gallwalls: [
                    { walls: 'wfoo1', id: 1, description: O.of('') },
                    { walls: 'wfoo2', id: 2, description: O.of('') },
                ],
                gallshape: [
                    { shape: 'sfoo1', id: 1, description: O.of('') },
                    { shape: 'sfoo2', id: 2, description: O.of('') },
                ],
                galllocation: [
                    { loc: 'lfoo1', id: 1, description: O.of('') },
                    { loc: 'lfoo2', id: 2, description: O.of('') },
                ],
                galltexture: [{ tex: 'tfoo', id: 1, description: O.of('') }],
            },
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
                walls: [],
                shape: [],
                locations: [],
                textures: [],
            }),
        ).toBeTruthy();
    });
});
