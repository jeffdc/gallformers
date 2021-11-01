import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetServerSideProps } from 'next';
import { ParsedUrlQuery } from 'querystring';
import React from 'react';
import { Button, Col, Row } from 'react-bootstrap';
import * as yup from 'yup';
import { RenameEvent } from '../../components/editname';
import useAdmin from '../../hooks/useadmin';
import { AdminFormFields } from '../../hooks/useAPIs';
import { extractQueryParam } from '../../libs/api/apipage';
import { ALL_FAMILY_TYPES } from '../../libs/api/apitypes';
import { FAMILY, TaxonomyEntry, TaxonomyUpsertFields } from '../../libs/api/taxonomy';
import { allFamilies } from '../../libs/db/taxonomy';
import Admin from '../../libs/pages/admin';
import { genOptions } from '../../libs/utils/forms';
import { mightFailWithArray } from '../../libs/utils/util';

const schema = yup.object().shape({
    mainField: yup.mixed().required(),
    description: yup.string().required(),
});

// We have to remove the parent property as the Form library can not handle circular references in the data.
type TaxFamily = Omit<TaxonomyEntry, 'parent'>;

type FormFields = AdminFormFields<TaxFamily> & Omit<TaxFamily, 'id' | 'name' | 'type'>;

type Props = {
    id: string;
    fs: TaxFamily[];
};

const renameFamily = async (s: TaxFamily, e: RenameEvent) => ({
    ...s,
    name: e.new,
});

const toUpsertFields = (fields: FormFields, name: string, id: number): TaxonomyUpsertFields => {
    return {
        ...fields,
        name: name,
        type: 'family',
        id: id,
        species: [],
        parent: O.none,
    };
};

const updatedFormFields = async (fam: TaxFamily | undefined): Promise<FormFields> => {
    if (fam != undefined) {
        return {
            mainField: [fam],
            description: fam.description,
            del: false,
        };
    }

    return {
        mainField: [],
        description: '',
        del: false,
    };
};

const createNewFamily = (name: string): TaxFamily => ({
    name: name,
    description: '',
    id: -1,
    type: FAMILY,
});

const Family = ({ id, fs }: Props): JSX.Element => {
    const {
        selected,
        showRenameModal,
        setShowRenameModal,
        isValid,
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

    return (
        <Admin
            type="Family"
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
                <h4>Add or Edit a Family</h4>
                <Row className="form-group">
                    <Col>
                        <Row>
                            <Col>Name:</Col>
                        </Row>
                        <Row>
                            <Col>{mainField('name', 'Family')}</Col>
                            {selected && (
                                <Col xs={1}>
                                    <Button variant="secondary" className="btn-sm" onClick={() => setShowRenameModal(true)}>
                                        Rename
                                    </Button>
                                </Col>
                            )}
                        </Row>
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        Description:
                        <select {...form.register('description')} className="form-control" disabled={!selected}>
                            {genOptions(ALL_FAMILY_TYPES)}
                        </select>
                        {form.formState.errors.description && (
                            <span className="text-danger">You must provide the description.</span>
                        )}
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        <input type="submit" className="button" value="Submit" disabled={!selected || !isValid} />
                    </Col>
                    <Col>
                        {deleteButton(
                            'Caution. If there are any species (galls or hosts) assigned to this Family they too will be deleted.',
                        )}
                    </Col>
                </Row>
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
            fs: await mightFailWithArray<TaxonomyEntry>()(allFamilies()),
        },
    };
};
export default Family;
