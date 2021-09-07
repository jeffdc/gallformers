import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetServerSideProps } from 'next';
import { ParsedUrlQuery } from 'querystring';
import React from 'react';
import { Button, Col, Form, FormGroup, Row } from 'react-bootstrap';
import 'react-simple-tree-menu/dist/main.css';
import * as yup from 'yup';
import EditableDataTable, { EditableTableColumn } from '../../components/EditableDataTable';
import { RenameEvent } from '../../components/editname';
import useAdmin from '../../hooks/useadmin';
import { AdminFormFields } from '../../hooks/useAPIs';
import { extractQueryParam } from '../../libs/api/apipage';
import { ALL_FAMILY_TYPES } from '../../libs/api/apitypes';
import { EMPTY_TAXONOMYENTRY, FAMILY, FamilyUpsertFields, FamilyWithGenera, Genus } from '../../libs/api/taxonomy';
import { allFamiliesWithGenera } from '../../libs/db/taxonomy';
import Admin from '../../libs/pages/admin';
import { TABLE_CUSTOM_STYLES } from '../../libs/utils/DataTableConstants';
import { genOptions } from '../../libs/utils/forms';
import { mightFailWithArray } from '../../libs/utils/util';

const schema = yup.object().shape({
    mainField: yup.mixed().required(),
    description: yup.string().required(),
});

// We have to remove the parent property as the Form library can not handle circular references in the data.
// type TaxFamily = Omit<FamilyWithGenera, 'taxonomy'>;
type TaxFamily = Omit<FamilyWithGenera, 'parent'>;

type FormFields = AdminFormFields<TaxFamily> & Pick<TaxFamily, 'description' | 'genera'>;

type Props = {
    id: string;
    fs: FamilyWithGenera[];
};

const renameFamily = async (s: TaxFamily, e: RenameEvent) => ({
    ...s,
    name: e.new,
});

const updatedFormFields = async (fam: TaxFamily | undefined): Promise<FormFields> => {
    if (fam != undefined) {
        return {
            mainField: [fam],
            description: fam.description,
            del: false,
            genera: fam.genera,
        };
    }

    return {
        mainField: [],
        description: '',
        del: false,
        genera: [],
    };
};

const toUpsertFields = (fields: FormFields, name: string, id: number): FamilyUpsertFields => {
    console.log(`JDC: update fields ${JSON.stringify(fields, null, '  ')}`);
    return {
        ...fields,
        name: name,
        type: 'family',
        id: id,
        description: fields.description ?? '',
        genera: fields.genera ?? [],
    };
};

const createNewFamily = (name: string): TaxFamily => ({
    name: name,
    description: '',
    id: -1,
    type: FAMILY,
    genera: [],
});

const columns: EditableTableColumn<Genus>[] = [
    {
        id: 'name',
        name: 'Genus',
        selector: (row: Genus) => row.name,
        sortable: true,
        wrap: true,
        maxWidth: '300px',
        editKey: 'name',
    },
    {
        id: 'description',
        name: 'Friendly Name',
        selector: (row: Genus) => row.description,
        wrap: true,
        editKey: 'description',
    },
];

const TaxonomyAdmin = ({ id, fs }: Props): JSX.Element => {
    const {
        selected,
        setSelected,
        showRenameModal,
        setShowRenameModal,
        error,
        setError,
        deleteResults,
        setDeleteResults,
        renameCallback,
        form,
        formSubmit,
        mainField,
        deleteButton,
    } = useAdmin(
        'Family',
        id,
        fs,
        renameFamily,
        toUpsertFields,
        { keyProp: 'name', delEndpoint: '../api/family/', upsertEndpoint: '../api/family/upsert' },
        schema,
        updatedFormFields,
        false,
        createNewFamily,
    );

    const updateGenera = (genera: Genus[]) => {
        if (selected) {
            setSelected({ ...selected, genera: genera });
        }
    };

    const moveSelected = (g: Genus[]) => {
        //TODO: move genus workflow...
    };

    return (
        <Admin
            type="Taxonomy"
            keyField="name"
            editName={{ getDefault: () => selected?.name, renameCallback: renameCallback }}
            setShowModal={setShowRenameModal}
            showModal={showRenameModal}
            setError={setError}
            error={error}
            setDeleteResults={setDeleteResults}
            deleteResults={deleteResults}
            selected={selected}
        >
            <form onSubmit={form.handleSubmit(formSubmit)} className="m-4 pr-4">
                <h4>Manage Taxonomy</h4>
                <Form.Row>
                    <FormGroup as={Col}>
                        <Form.Label>Family Name:</Form.Label>
                        {mainField('name', 'Family')}
                    </FormGroup>
                    <FormGroup as={Col}>
                        <Form.Label>Description:</Form.Label>
                        <select {...form.register('description')} className="form-control">
                            {genOptions(ALL_FAMILY_TYPES)}
                        </select>
                        {form.formState.errors.description && (
                            <span className="text-danger">You must provide the description.</span>
                        )}
                    </FormGroup>
                </Form.Row>
                <Row>
                    <Col>
                        <Form.Label>Genera:</Form.Label>
                    </Col>
                </Row>
                <EditableDataTable
                    keyField={'id'}
                    data={selected?.genera ?? []}
                    columns={columns}
                    striped
                    responsive={false}
                    defaultSortFieldId={'name'}
                    customStyles={TABLE_CUSTOM_STYLES}
                    createEmpty={() => EMPTY_TAXONOMYENTRY}
                    update={updateGenera}
                    customActions={[{ name: 'Move', onUpdate: moveSelected }]}
                />
                <hr />
                <Form.Row>
                    <Col xs={2} className="mr-3">
                        <Button variant="primary" type="submit" value="Submit" disabled={!selected}>
                            Submit
                        </Button>
                    </Col>
                    {selected && (
                        <Col>
                            <Button variant="secondary" className="button" onClick={() => setShowRenameModal(true)}>
                                Rename
                            </Button>
                        </Col>
                    )}
                    <Col>
                        {deleteButton(
                            'Caution. If there are any species (galls or hosts) assigned to this Family they too will be deleted.',
                        )}
                    </Col>
                </Form.Row>
            </form>
        </Admin>
    );
};

export const getServerSideProps: GetServerSideProps = async (context: { query: ParsedUrlQuery }) => {
    const queryParam = 'id';
    // eslint-disable-next-line prettier/prettier
    const id = pipe(
        extractQueryParam(context.query, queryParam),
        O.getOrElse(constant('')),
    );

    return {
        props: {
            id: id,
            fs: await mightFailWithArray<FamilyWithGenera>()(allFamiliesWithGenera()),
        },
    };
};

export default TaxonomyAdmin;