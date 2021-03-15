import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetServerSideProps } from 'next';
import { useRouter } from 'next/router';
import { ParsedUrlQuery } from 'querystring';
import React from 'react';
import { Button, Col, Row } from 'react-bootstrap';
import * as yup from 'yup';
import ControlledTypeahead from '../../components/controlledtypeahead';
import useAdmin from '../../hooks/useadmin';
import { AdminFormFields } from '../../hooks/useAPIs';
import { extractQueryParam } from '../../libs/api/apipage';
import { ALL_FAMILY_TYPES } from '../../libs/api/apitypes';
import { TaxonomyEntry, TaxonomyUpsertFields } from '../../libs/api/taxonomy';
import { allFamilies } from '../../libs/db/taxonomy';
import Admin from '../../libs/pages/admin';
import { genOptions } from '../../libs/utils/forms';
import { mightFailWithArray } from '../../libs/utils/util';

const schema = yup.object().shape({
    value: yup.mixed().required(),
    description: yup.string().required(),
});

type Props = {
    id: string;
    fs: TaxonomyEntry[];
};

const updateFamily = (s: TaxonomyEntry, newValue: string) => ({
    ...s,
    name: newValue,
});

const emptyForm = {
    value: [],
    description: '',
};

const convertToFields = (s: TaxonomyEntry): FormFields => ({
    ...s,
    del: false,
    value: [s],
});

const toUpsertFields = (fields: FormFields, name: string, id: number): TaxonomyUpsertFields => {
    return {
        ...fields,
        name: name,
        type: 'family',
        id: id,
        species: [],
    };
};

type FormFields = AdminFormFields<TaxonomyEntry> & Omit<TaxonomyEntry, 'id' | 'name'>;

const Family = ({ id, fs }: Props): JSX.Element => {
    const {
        data,
        selected,
        setSelected,
        showRenameModal,
        setShowRenameModal,
        error,
        setError,
        deleteResults,
        setDeleteResults,
        renameWithNewValue,
        form,
        formSubmit,
    } = useAdmin(
        'Family',
        id,
        fs,
        updateFamily,
        convertToFields,
        toUpsertFields,
        { keyProp: 'name', delEndpoint: '../api/family/', upsertEndpoint: '../api/family/upsert' },
        schema,
        emptyForm,
    );

    const router = useRouter();

    const onSubmit = async (fields: FormFields) => {
        await formSubmit(fields);
    };

    return (
        <Admin
            type="Family"
            keyField="name"
            editName={{ getDefault: () => selected?.name, setNewValue: renameWithNewValue(onSubmit) }}
            setShowModal={setShowRenameModal}
            showModal={showRenameModal}
            setError={setError}
            error={error}
            setDeleteResults={setDeleteResults}
            deleteResults={deleteResults}
        >
            <form onSubmit={form.handleSubmit(onSubmit)} className="m-4 pr-4">
                <h4>Add or Edit a Family</h4>
                <Row className="form-group">
                    <Col>
                        <Row>
                            <Col>Name:</Col>
                        </Row>
                        <Row>
                            <Col>
                                <ControlledTypeahead
                                    control={form.control}
                                    name="value"
                                    placeholder="Name"
                                    options={data}
                                    labelKey="name"
                                    clearButton
                                    isInvalid={!!form.errors.value}
                                    newSelectionPrefix="Add a new Family: "
                                    allowNew={true}
                                    onChangeWithNew={(e, isNew) => {
                                        if (isNew || !e[0]) {
                                            setSelected(undefined);
                                            router.replace(``, undefined, { shallow: true });
                                        } else {
                                            setSelected(e[0]);
                                            router.replace(`?id=${e[0].id}`, undefined, { shallow: true });
                                        }
                                    }}
                                />
                                {form.errors.value && <span className="text-danger">The Name is required.</span>}
                            </Col>
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
                        <select name="description" className="form-control" ref={form.register}>
                            {genOptions(ALL_FAMILY_TYPES)}
                        </select>
                        {form.errors.description && <span className="text-danger">You must provide the description.</span>}
                    </Col>
                </Row>
                <Row className="fromGroup" hidden={!selected}>
                    <Col xs="1">Delete?:</Col>
                    <Col className="mr-auto">
                        <input name="del" type="checkbox" className="form-check-input" ref={form.register} />
                    </Col>
                    <Col xs="8">
                        <em className="text-danger">
                            Caution. If there are any species (galls or hosts) assigned to this Family they too will be deleted.
                        </em>
                    </Col>
                </Row>
                <Row className="form-input">
                    <Col>
                        <input type="submit" className="button" value="Submit" />
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
