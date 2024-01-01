import * as O from 'fp-ts/lib/Option';
import { constant, pipe } from 'fp-ts/lib/function';
import * as t from 'io-ts';
import { GetServerSideProps } from 'next';
import { ParsedUrlQuery } from 'querystring';
import { Alert, Button, Col, Row } from 'react-bootstrap';
import { RenameEvent } from '../../components/editname';
import useAdmin, { AdminFormFields, adminFormFieldsSchema } from '../../hooks/useadmin';
import { extractQueryParam } from '../../libs/api/apipage';
import { PLACE_TYPES, PlaceNoTreeApi, PlaceNoTreeApiSchema, PlaceNoTreeUpsertFields } from '../../libs/api/apitypes';
import Admin from '../../libs/pages/admin';

type Props = {
    id: string;
};

const schema = t.intersection([adminFormFieldsSchema(PlaceNoTreeApiSchema), PlaceNoTreeApiSchema]);

type FormFields = AdminFormFields<PlaceNoTreeApi> & Omit<PlaceNoTreeApi, 'id' | 'name'>;

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

const mainFieldName = 'name';

const PlaceAdmin = ({ id }: Props): JSX.Element => {
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
        nameExists,
        form,
        formSubmit,
        mainField,
        deleteButton,
    } = useAdmin(
        'Place',
        mainFieldName,
        id,
        renamePlace,
        toUpsertFields,
        {
            delEndpoint: '../api/place/',
            upsertEndpoint: '../api/place/upsert',
            nameExistsEndpoint: (s: string) => `/api/place?name=${s}`,
        },
        schema,
        updatedFormFields,
        false,
        createNewPlace,
    );

    return (
        <Admin
            type="Place"
            keyField={mainFieldName}
            editName={{ getDefault: () => selected?.name, renameCallback: renameCallback, nameExistsCallback: nameExists }}
            setShowModal={setShowModal}
            showModal={showModal}
            setError={setError}
            error={error}
            setDeleteResults={setDeleteResults}
            deleteResults={deleteResults}
            selected={selected}
            superAdmin={true}
        >
            <form onSubmit={form.handleSubmit(formSubmit)} className="m-4 pe-4">
                <h4>Add/Edit Places</h4>
                <Alert variant="info">
                    This is really just a stub page for now. Much work still needs to be done to support Place hierarchies as well
                    as Place aggregations. You can do basic creation and editing but it is not currently possible to manage
                    anything other than US States or Canadian Provinces. Since these are all already in here it is doubtful that
                    this will ever be used in its current form. If you are looking to add Range information go to the Host admin
                    and add it there.
                </Alert>
                <Row className="my-1">
                    <Col>
                        <Row>
                            <Col>Name:</Col>
                        </Row>
                        <Row>
                            <Col>{mainField('Place', { searchEndpoint: (s) => `../api/place?q=${s}` })}</Col>
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
                <Row className="my-1">
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
                        <select {...form.register('type')} aria-placeholder="Type" className="form-control" disabled={!selected}>
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
                        <Button variant="primary" type="submit" value="Save Changes" disabled={!selected || !isValid}>
                            Save Changes
                        </Button>
                    </Col>
                    <Col>{deleteButton('Caution. The Place will be PERMANENTLY deleted.')}</Col>
                </Row>
            </form>
        </Admin>
    );
};

export const getServerSideProps: GetServerSideProps = async (context: { query: ParsedUrlQuery }) => {
    return {
        props: {
            id: pipe(extractQueryParam(context.query, 'id'), O.getOrElse(constant(''))),
        },
    };
};
export default PlaceAdmin;
