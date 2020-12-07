import { alignment, cells, color, family, shape, walls } from '@prisma/client';
import { GallApi, GallLocation, GallTaxon, GallTexture, SearchQuery } from '../../../libs/api/apitypes';
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
    const g = {
        abundance: null,
        abundance_id: 1,
        commonnames: null,
        description: 'The chicken gall...',
        family: {} as family,
        family_id: 1,
        gall: {
            alignment: null,
            cells: null,
            color: null,
            detachable: 0,
            galllocation: [],
            galltexture: [],
            shape: null,
            walls: null,
        },
        genus: 'Gallus',
        hosts: [],
        id: 1,
        name: 'Gallus gallus',
        speciessource: [],
        synonyms: null,
        taxoncode: GallTaxon,
    } as GallApi;

    const q = {
        alignment: undefined,
        cells: undefined,
        color: undefined,
        detachable: 'no',
        host: '',
        locations: undefined,
        shape: undefined,
        textures: [],
        walls: undefined,
    } as SearchQuery;

    // helper to create test galls in the tests.
    const makeG = (
        k: keyof GallApi['gall'],
        v: alignment | cells | color | number | GallLocation[] | GallTexture[] | shape | walls,
    ) => ({
        ...g,
        gall: { ...g.gall, [k]: v },
    });

    test('Should not fail to match for any search field that is undefined, empty string, or empty array', () => {
        expect(checkGall(g, q)).toBeTruthy();
        expect(checkGall(makeG('alignment', { alignment: '', id: 1, description: '' }), q)).toBeTruthy();
        expect(checkGall(makeG('cells', { cells: '', id: 1, description: '' }), q)).toBeTruthy();
        expect(checkGall(makeG('color', { color: '', id: 1, description: '' }), q)).toBeTruthy();
        expect(checkGall(makeG('shape', { shape: '', id: 1, description: '' }), q)).toBeTruthy();
        expect(checkGall(makeG('walls', { walls: '', id: 1, description: '' }), q)).toBeTruthy();
        expect(checkGall(makeG('galllocation', [{ location: { location: '', id: 1, description: '' } }]), q)).toBeTruthy();
        expect(checkGall(makeG('galltexture', [{ texture: { texture: '', id: 1, description: '' } }]), q)).toBeTruthy();
    });

    test('Should match when provided query has single matches', () => {
        expect(
            checkGall(makeG('alignment', { alignment: 'foo', id: 1, description: '' }), {
                ...q,
                alignment: 'foo',
            }),
        ).toBeTruthy();
        expect(
            checkGall(makeG('cells', { cells: 'foo', id: 1, description: '' }), {
                ...q,
                cells: 'foo',
            }),
        ).toBeTruthy();
        expect(
            checkGall(makeG('color', { color: 'foo', id: 1, description: '' }), {
                ...q,
                color: 'foo',
            }),
        ).toBeTruthy();
        expect(
            checkGall(makeG('shape', { shape: 'foo', id: 1, description: '' }), {
                ...q,
                shape: 'foo',
            }),
        ).toBeTruthy();
        expect(
            checkGall(makeG('walls', { walls: 'foo', id: 1, description: '' }), {
                ...q,
                walls: 'foo',
            }),
        ).toBeTruthy();
        expect(
            checkGall(makeG('galllocation', [{ location: { location: 'foo', id: 1, description: '' } }]), {
                ...q,
                locations: ['foo'],
            }),
        ).toBeTruthy();
        expect(
            checkGall(makeG('galltexture', [{ texture: { texture: 'foo', id: 1, description: '' } }]), {
                ...q,
                textures: ['foo'],
            }),
        ).toBeTruthy();
    });

    test('Should match when provided query has multiple matches', () => {
        expect(
            checkGall(
                {
                    ...g,
                    gall: {
                        ...g.gall,
                        alignment: { alignment: 'afoo', id: 1, description: ' ' },
                        color: { color: 'cofoo', id: 1 },
                        cells: { cells: 'cefoo', id: 1, description: ' ' },
                        shape: { shape: 'sfoo', id: 1, description: ' ' },
                        walls: { walls: 'wfoo', id: 1, description: ' ' },
                        galllocation: [{ location: { location: 'lfoo', id: 1, description: '' } }],
                        galltexture: [{ texture: { texture: 'tfoo', id: 1, description: '' } }],
                    },
                },
                {
                    ...q,
                    alignment: 'afoo',
                    color: 'cofoo',
                    cells: 'cefoo',
                    shape: 'sfoo',
                    walls: 'wfoo',
                    locations: ['lfoo'],
                    textures: ['tfoo'],
                },
            ),
        ).toBeTruthy();
    });

    test('Handles array types correctly (location and texture)', () => {
        const theG = {
            ...g,
            gall: {
                ...g.gall,
                galllocation: [
                    { location: { location: 'lfoo1', id: 1, description: '' } },
                    { location: { location: 'lfoo2', id: 2, description: '' } },
                ],
                galltexture: [{ texture: { texture: 'tfoo', id: 1, description: '' } }],
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
                locations: ['lfoo1'],
                textures: ['tfoo'],
            }),
        ).toBeTruthy();

        expect(
            checkGall(theG, {
                ...q,
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
                locations: [],
                textures: [],
            }),
        ).toBeTruthy();
    });
});
