import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import FilterTerms, { Props } from '../../../../pages/admin/filterterms';
import * as O from 'fp-ts/lib/Option';

jest.mock('next-auth/react', () => {
    const originalModule = jest.requireActual('next-auth/react');
    const mockSession = {
        expires: new Date(Date.now() + 2 * 86400).toISOString(),
        user: { username: 'admin' },
    };
    return {
        __esModule: true,
        ...originalModule,
        useSession: jest.fn(() => {
            return { data: mockSession, status: 'authenticated' };
        }),
    };
});

const props: Props = {
    alignments: [{ id: 0, field: 'drooping', description: O.of('the definition') }],
    cells: [],
    colors: [],
    forms: [],
    locations: [],
    shapes: [],
    textures: [],
    walls: [],
};
const renderFilterForm = () => {
    return {
        user: userEvent.setup(),
        ...render(<FilterTerms {...props} />),
    };
};

it('should have Submit disabled with no valid selection', async () => {
    const { user, container, baseElement } = renderFilterForm();

    const submitButton = screen.getByRole('button', { name: /Save Changes/i });
    const fieldTypeField: HTMLSelectElement = screen.getByTitle('fieldType');
    const fieldField: HTMLInputElement = screen.getByPlaceholderText('Field');
    // const fieldOptions = screen.getByRole('listbox', { name: /menu-options/i });
    const descriptionField: HTMLInputElement = screen.getByPlaceholderText('description');

    expect(fieldTypeField.options.length).toBe(Object.keys(props).length);
    expect(fieldTypeField.value).toBe('alignments');
    // expect(fieldOptions.children.length).toBe(props.alignments.length);
    expect(submitButton).toBeDisabled();
    expect(descriptionField).toBeDisabled();

    // set a value but not a description
    await user.selectOptions(fieldField, 'drooping');
    expect(fieldField.value).toBe('drooping');
    expect(submitButton).toBeDisabled();
    expect(descriptionField).toBeEnabled();
    expect(fieldField.validity.valid).toBeTruthy();

    // now set a description and it should validate
    await user.type(descriptionField, 'Test input');
    expect(descriptionField.validity.valid).toBeTruthy();
    expect(submitButton).toBeEnabled();
    await user.click(submitButton);

    expect(submitButton).toBeDisabled();
});
