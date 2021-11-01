import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetServerSideProps } from 'next';
import { ParsedUrlQuery } from 'querystring';
import React from 'react';
import { Alert, Button, Col, Row } from 'react-bootstrap';
import * as yup from 'yup';
import { RenameEvent } from '../../components/editname';
import useAdmin from '../../hooks/useadmin';
import { AdminFormFields } from '../../hooks/useAPIs';
import { extractQueryParam } from '../../libs/api/apipage';
import { PlaceNoTreeApi, PlaceNoTreeUpsertFields, PLACE_TYPES } from '../../libs/api/apitypes';
import { getPlaces } from '../../libs/db/place';
import Admin from '../../libs/pages/admin';
import { mightFailWithArray } from '../../libs/utils/util';

const schema = yup.object().shape({
    mainField: yup.mixed().required(),
    code: yup.string().required(),
    type: yup.string().required(),
});

type Props = {
    id: string;
    places: PlaceNoTreeApi[];
};

type FormFields = AdminFormFields<PlaceNoTreeApi> & Pick<PlaceNoTreeApi, 'code' | 'type'>;

const renamePlace = async (s: PlaceNoTreeApi, e: RenameEvent): Promise<PlaceNoTreeApi> => ({
    ...s,
    name: e.new,
});

const toUpsertFields = (fields: FormFields, name: string, id: number): PlaceNoTreeUpsertFields => {
    return {
        ...fields,
        id: id,
        name: name,
    };
};

const updatedFormFields = async (e: PlaceNoTreeApi | undefined): Promise<FormFields> => {
    if (e != undefined) {
        return {
            mainField: [e],
            code: e.code,
            type: e.type,
            del: false,
        };
    }

    return {
        mainField: [],
        code: '',
        type: '',
        del: false,
    };
};

const createNewPlace = (name: string): PlaceNoTreeApi => ({
    id: -1,
    name: name,
    code: '',
    type: 'state',
});

const PlaceAdmin = ({ id, places }: Props): JSX.Element => {
    const {
        selected,
        showRenameModal: showModal,
        setShowRenameModal: setShowModal,
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
        'Place',
        id,
        places,
        renamePlace,
        toUpsertFields,
        { keyProp: 'name', delEndpoint: '../api/place/', upsertEndpoint: '../api/place/upsert' },
        schema,
        updatedFormFields,
        false,
        createNewPlace,
    );

    return (
        <Admin
            type="Place"
            keyField="name"
            editName={{ getDefault: () => selected?.name, renameCallback: renameCallback }}
            setShowModal={setShowModal}
            showModal={showModal}
            setError={setError}
            error={error}
            setDeleteResults={setDeleteResults}
            deleteResults={deleteResults}
            selected={selected}
        >
            <form onSubmit={form.handleSubmit(formSubmit)} className="m-4 pr-4">
                <h4>Add/Edit Places</h4>
                <Alert variant="info">
                    This is really just a stub page for now. Much work still needs to be done to support Place hierachies as well
                    as Place aggregations. You can do basic creation and editing but it is not currently possible to manage
                    anything other than US States or Canadian Provinces. Since these are all already in here it is doubtful that
                    this will ever be used in its current form. If you are looking to add Range information go to the Host admin
                    and add it there.
                </Alert>
                <Row className="form-group">
                    <Col>
                        <Row>
                            <Col>Name:</Col>
                        </Row>
                        <Row>
                            <Col>{mainField('name', 'Name')}</Col>
                            {selected && (
                                <Col xs={1}>
                                    <Button variant="secondary" className="btn-sm" onClick={() => setShowModal(true)}>
                                        Rename
                                    </Button>
                                </Col>
                            )}
                        </Row>
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        Code (required):
                        <input
                            {...form.register('code')}
                            type="text"
                            placeholder="Code"
                            className="form-control"
                            disabled={!selected}
                        />
                        {form.formState.errors.code && <span className="text-danger">You must provide the code.</span>}
                    </Col>
                    <Col>
                        Type (required):
                        <select {...form.register('type')} placeholder="Type" className="form-control" disabled={!selected}>
                            {PLACE_TYPES.map((t) => (
                                <option key={t}>{t}</option>
                            ))}
                        </select>{' '}
                        {form.formState.errors.type && (
                            <span className="text-danger">You must provide the Type of the Place.</span>
                        )}
                    </Col>
                </Row>
                <Row className="form-input">
                    <Col>
                        <input type="submit" className="button" value="Submit" disabled={!selected || !isValid} />
                    </Col>
                    <Col>{deleteButton('Caution. The Place will be deleted.')}</Col>
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
            places: await mightFailWithArray<PlaceNoTreeApi>()(getPlaces()),
        },
    };
};
export default PlaceAdmin;
