import fc from 'fast-check';
import { testables, FormFields } from '../../../pages/admin/host';

const { extractGenus, Schema } = testables;

describe('Schema validation', () => {
    const fields: FormFields = {
        abundance: [],
        commonnames: '',
        family: [],
        genus: '',
        value: [],
        synonyms: '',
        del: false,
    };
    const fieldsWithFam = {
        ...fields,
        family: 'TheFam',
    };

    test('fail on invalid host name', () => {
        expect(Schema.isValidSync(fieldsWithFam)).toBeFalsy();
        expect(Schema.isValidSync({ ...fieldsWithFam, value: [{ name: '' }] })).toBeFalsy();
        expect(Schema.isValidSync({ ...fieldsWithFam, value: [{ name: 'Foo' }] })).toBeFalsy();
        expect(Schema.isValidSync({ ...fieldsWithFam, value: [{ name: 'Foo Bar' }] })).toBeFalsy();
        expect(Schema.isValidSync({ ...fieldsWithFam, value: [{ name: 'Foo bar' }, { name: 'Bar baz' }] })).toBeFalsy();
        expect(Schema.isValidSync({ ...fieldsWithFam, value: [{ notname: 'Foo bar' }] })).toBeFalsy();
    });

    test('pass on valid host name', () => {
        expect(Schema.isValidSync({ ...fieldsWithFam, value: [{ name: 'Foo bar' }] })).toBeTruthy();
    });
});

describe('extractGenus tests', () => {
    test('it must act as the identity if passed in a string whose format is not conformant', () => {
        fc.property(
            fc.string().filter((s) => !s.includes(' ')),
            (s) => expect(extractGenus(s)).toBe(s),
        );
    });

    test('it must extract the genus when passed a conformant string', () => {
        expect(extractGenus('Foo bar')).toBe('Foo');
    });
});
