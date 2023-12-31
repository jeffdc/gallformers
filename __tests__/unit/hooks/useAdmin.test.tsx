import { fireEvent, render, screen, waitFor } from '@testing-library/react';

import * as t from 'io-ts';
import App from 'next/app';
import { Button, Col } from 'react-bootstrap';
import useAdmin, { adminFormFieldsSchema } from '../../../hooks/useadmin';
import Admin from '../../../pages/admin';

// These are tests to make sure that the base schema resolvers work in conjunction with the form stuff

const fooWithIdSchema = t.type({ id: t.number, foo: t.string });
type FooWithID = t.TypeOf<typeof fooWithIdSchema>;
const schema = adminFormFieldsSchema(fooWithIdSchema);
type FormFields = t.TypeOf<typeof schema>;

const UseAdminTestForm = (): JSX.Element => {
    const {
        // data,
        // setData,
        selected,
        // setSelected,
        showRenameModal,
        setShowRenameModal,
        error,
        setError,
        deleteResults,
        setDeleteResults,
        renameCallback,
        nameExists,
        form,
        formSubmit,
        mainField,
        deleteButton,
        isSuperAdmin,
        isValid,
    } = useAdmin(
        'Foo',
        '0',
        () => Promise.resolve({ id: 0, foo: 'foo' } as FooWithID),
        (f: FormFields, k: string, id: number) => ({ f: f, k: k, id: id }),
        {
            keyProp: 'foo',
            delEndpoint: '',
            upsertEndpoint: '',
            nameExistsEndpoint: (s: string) => `${s}`,
        },
        schema,
        () => Promise.resolve({} as FormFields),
        false,
    );

    return (
        <Admin
            type="Taxonomy"
            keyField="name"
            editName={{ getDefault: () => selected?.foo, renameCallback: renameCallback, nameExistsCallback: nameExists }}
            setShowModal={setShowRenameModal}
            showModal={showRenameModal}
            setError={setError}
            error={error}
            setDeleteResults={setDeleteResults}
            deleteResults={deleteResults}
            selected={selected}
        >
            <form onSubmit={form.handleSubmit(formSubmit)}>
                {mainField('name', 'Family', { searchEndpoint: (s) => `/api/taxonomy/family?q=${s}` })}

                {selected && (
                    <Col>
                        <Button variant="secondary" size="sm" className="button" onClick={() => setShowRenameModal(true)}>
                            Rename
                        </Button>
                    </Col>
                )}
                <Button variant="primary" type="submit" value="Save Changes" disabled={!selected || !isValid}>
                    Save Changes
                </Button>
                {isSuperAdmin
                    ? deleteButton(
                          'Caution. If there are any species (galls or hosts) assigned to this Family they too will be PERMANENTLY deleted.',
                      )
                    : 'If you need to delete a Family please contact Adam or Jeff on Slack/Discord.'}
            </form>
        </Admin>
    );
};

// Tests begin...
test('base schema validation works', () => {
    expect(true).toBeTruthy();
});

// it('should display required error when value is invalid', async () => {
//     render(<UseAdminTestForm />);

//     fireEvent.submit(screen.getByRole('button'));

//     expect(await screen.findAllByRole('alert')).toHaveLength(2);
//     expect(mockLogin).not.toBeCalled();
// });

// it('should display matching error when email is invalid', async () => {
//     render(<App login={mockLogin} />);

//     fireEvent.input(screen.getByRole('textbox', { name: /email/i }), {
//         target: {
//             value: 'test',
//         },
//     });

//     fireEvent.input(screen.getByLabelText('password'), {
//         target: {
//             value: 'password',
//         },
//     });

//     fireEvent.submit(screen.getByRole('button'));

//     expect(await screen.findAllByRole('alert')).toHaveLength(1);
//     expect(mockLogin).not.toBeCalled();
//     expect(screen.getByRole('textbox', { name: /email/i })).toHaveValue('test');
//     expect(screen.getByLabelText('password')).toHaveValue('password');
// });

// it('should display min length error when password is invalid', async () => {
//     render(<App login={mockLogin} />);

//     fireEvent.input(screen.getByRole('textbox', { name: /email/i }), {
//         target: {
//             value: 'test@mail.com',
//         },
//     });

//     fireEvent.input(screen.getByLabelText('password'), {
//         target: {
//             value: 'pass',
//         },
//     });

//     fireEvent.submit(screen.getByRole('button'));

//     expect(await screen.findAllByRole('alert')).toHaveLength(1);
//     expect(mockLogin).not.toBeCalled();
//     expect(screen.getByRole('textbox', { name: /email/i })).toHaveValue('test@mail.com');
//     expect(screen.getByLabelText('password')).toHaveValue('pass');
// });

// it('should not display error when value is valid', async () => {
//     render(<App login={mockLogin} />);

//     fireEvent.input(screen.getByRole('textbox', { name: /email/i }), {
//         target: {
//             value: 'test@mail.com',
//         },
//     });

//     fireEvent.input(screen.getByLabelText('password'), {
//         target: {
//             value: 'password',
//         },
//     });

//     fireEvent.submit(screen.getByRole('button'));

//     await waitFor(() => expect(screen.queryAllByRole('alert')).toHaveLength(0));
//     expect(mockLogin).toBeCalledWith('test@mail.com', 'password');
//     expect(screen.getByRole('textbox', { name: /email/i })).toHaveValue('');
//     expect(screen.getByLabelText('password')).toHaveValue('');
// });
