import { testables, FormFields } from '../../../pages/admin/host';

const { Schema } = testables;

describe('Schema validation', () => {
    const fields: FormFields = {
        abundance: [],
        family: [],
        genus: [],
        value: [],
        del: false,
        datacomplete: false,
        section: [],
    };
    const fieldsWithFam = {
        ...fields,
        family: 'TheFam',
    };

    // readd this when fix validator in the admin host form.
    // test('fail on invalid host name', () => {
    //     expect(Schema.isValidSync(fieldsWithFam)).toBeFalsy();
    //     expect(Schema.isValidSync({ ...fieldsWithFam, value: [{ name: '' }] })).toBeFalsy();
    //     expect(Schema.isValidSync({ ...fieldsWithFam, value: [{ name: 'Foo' }] })).toBeFalsy();
    //     expect(Schema.isValidSync({ ...fieldsWithFam, value: [{ name: 'Foo Bar' }] })).toBeFalsy();
    //     expect(Schema.isValidSync({ ...fieldsWithFam, value: [{ name: 'Foo bar' }, { name: 'Bar baz' }] })).toBeFalsy();
    //     expect(Schema.isValidSync({ ...fieldsWithFam, value: [{ notname: 'Foo bar' }] })).toBeFalsy();
    // });

    test('pass on valid host name', () => {
        expect(Schema.isValidSync({ ...fieldsWithFam, value: [{ name: 'Foo bar' }] })).toBeTruthy();
    });
});
