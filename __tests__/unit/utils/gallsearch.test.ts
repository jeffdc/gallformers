import { family } from '@prisma/client';
import { GallApi, GallTaxon, SearchQuery } from '../../../libs/api/apitypes';
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

    test('Should not fail to match for any search field that is undefined, empty string, or empty array', () => {
        expect(checkGall(g, q)).toBeTruthy();
        expect(checkGall({ ...g, gall: { ...g.gall, alignment: { alignment: '', id: 1, description: '' } } }, q)).toBeTruthy();
    });
});
