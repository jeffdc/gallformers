import * as O from 'fp-ts/lib/Option';
import { constant, pipe } from 'fp-ts/lib/function';
import { GetServerSideProps } from 'next';
import { ParsedUrlQuery } from 'querystring';
import { Alert, Button, Col, Row } from 'react-bootstrap';
import { RenameEvent } from '../../components/editname';
import useAdmin, { AdminFormFields } from '../../hooks/useadmin';
import { extractQueryParam } from '../../libs/api/apipage';
import { PLACE_TYPES, PlaceNoTreeApi, PlaceNoTreeUpsertFields } from '../../libs/api/apitypes';
import Admin from '../../libs/pages/admin';

type Props = {
    id: string;
};

type FormFields = AdminFormFields<PlaceNoTreeApi> & Omit<PlaceNoTreeApi, 'id' | 'name'>;

const renamePlace = (s: PlaceNoTreeApi, e: RenameEvent): Promise<PlaceNoTreeApi> =>
    Promise.resolve({
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

const updatedFormFields = (e: PlaceNoTreeApi | undefined): Promise<FormFields> => {
    if (e != undefined) {
        return Promise.resolve({
            mainField: [e],
            code: e.code,
            type: e.type,
            del: false,
        });
    }

    return Promise.resolve({
        mainField: [],
        code: '',
        type: '',
        del: false,
    });
};

const createNewPlace = (name: string): PlaceNoTreeApi => ({
    id: -1,
    name: name,
    code: '',
    type: 'state',
});

const mainFieldName = 'name';

const PlaceAdmin = ({ id }: Props): JSX.Element => {
    const { selected, renameCallback, nameExists, ...adminForm } = useAdmin(
        'Place',
        mainFieldName,
        id,
        renamePlace,
        toUpsertFields,
        {
            delEndpoint: '../api/place/',
            upsertEndpoint: '../api/place/upsert',
            nameExistsEndpoint: (s: string) => `/api/place/name/${s}`,
        },
        updatedFormFields,
        false,
        createNewPlace,
    );

    return (
        <Admin
            type="Place"
            keyField={mainFieldName}
            editName={{ getDefault: () => selected?.name, renameCallback: renameCallback, nameExistsCallback: nameExists }}
            selected={selected}
            superAdmin={true}
            {...adminForm}
            saveButton={adminForm.saveButton()}
            deleteButton={adminForm.deleteButton('Caution. The Place will be PERMANENTLY deleted.', true)}
            form={adminForm.form}
            formSubmit={adminForm.formSubmit}
        >
            <>
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
                            <Col>{adminForm.mainField('Place', { searchEndpoint: (s) => `../api/place/?q=${s}` })}</Col>
                            {selected && (
                                <Col xs={1}>
                                    <Button
                                        variant="secondary"
                                        className="btn-sm"
                                        onClick={() => adminForm.setShowRenameModal(true)}
                                    >
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
                            {...adminForm.form.register('code', { required: true, disabled: !selected })}
                            type="text"
                            placeholder="Code"
                            className="form-control"
                        />
                        {adminForm.form.formState.errors.code && <span className="text-danger">You must provide the code.</span>}
                    </Col>
                    <Col>
                        Type (required):
                        <select
                            {...adminForm.form.register('type', { required: true, disabled: !selected })}
                            aria-placeholder="Type"
                            className="form-control"
                        >
                            {PLACE_TYPES.map((t) => (
                                <option key={t}>{t}</option>
                            ))}
                        </select>{' '}
                        {adminForm.form.formState.errors.type && (
                            <span className="text-danger">You must provide the Type of the Place.</span>
                        )}
                    </Col>
                </Row>
            </>
        </Admin>
    );
};

export const getServerSideProps: GetServerSideProps = async (context: { query: ParsedUrlQuery }) => {
    return Promise.resolve({
        props: {
            id: pipe(extractQueryParam(context.query, 'id'), O.getOrElse(constant(''))),
        },
    });
};
export default PlaceAdmin;
