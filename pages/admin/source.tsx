import * as O from 'fp-ts/lib/Option';
import { constant, pipe } from 'fp-ts/lib/function';
import { GetServerSideProps } from 'next';
import { ParsedUrlQuery } from 'querystring';
import { Button, Col, Row } from 'react-bootstrap';
import { RenameEvent } from '../../components/editname';
import useAdmin, { AdminFormFields } from '../../hooks/useadmin';
import { extractQueryParam } from '../../libs/api/apipage';
import { ImageLicenseValues, SourceApi, SourceUpsertFields } from '../../libs/api/apitypes';
import { allSources } from '../../libs/db/source';
import Admin from '../../libs/pages/admin';
import { mightFailWithArray } from '../../libs/utils/util';

type Props = {
    id: string;
    sources: SourceApi[];
};

type FormFields = AdminFormFields<SourceApi> & Omit<SourceApi, 'id' | 'title'>;

const renameSource = async (s: SourceApi, e: RenameEvent) => ({
    ...s,
    title: e.new,
});

const toUpsertFields = (fields: FormFields, name: string, id: number): SourceUpsertFields => {
    return {
        ...fields,
        id: id,
        title: name,
    };
};

const updatedFormFields = async (s: SourceApi | undefined): Promise<FormFields> => {
    if (s != undefined) {
        return {
            mainField: [s],
            author: s.author,
            pubyear: s.pubyear,
            link: s.link,
            citation: s.citation,
            datacomplete: s.datacomplete,
            license: s.license,
            licenselink: s.licenselink,
            del: false,
        };
    }

    return {
        mainField: [],
        author: '',
        pubyear: '',
        link: '',
        citation: '',
        datacomplete: false,
        license: '',
        licenselink: '',
        del: false,
    };
};

const createNewSource = (title: string): SourceApi => ({
    title: title,
    author: '',
    citation: '',
    id: -1,
    link: '',
    pubyear: '',
    datacomplete: false,
    license: '',
    licenselink: '',
});

const keyFieldName = 'title';

const Source = ({ id, sources }: Props): JSX.Element => {
    const { selected, renameCallback, nameExists, ...adminForm } = useAdmin(
        'Source',
        keyFieldName,
        id,
        renameSource,
        toUpsertFields,
        {
            delEndpoint: '../api/source/',
            upsertEndpoint: '../api/source/upsert',
            nameExistsEndpoint: (s: string) => `/api/source/title/${s}`,
        },
        updatedFormFields,
        false,
        createNewSource,
        sources,
    );

    return (
        <Admin
            selected={selected}
            type="Source"
            keyField={keyFieldName}
            editName={{ getDefault: () => selected?.title, renameCallback: renameCallback, nameExistsCallback: nameExists }}
            {...adminForm}
            deleteButton={adminForm.deleteButton(
                'Caution. All data associated with this Source will be PERMANENTLY deleted.',
                true,
            )}
            saveButton={adminForm.saveButton()}
        >
            <>
                <h4>Add/Edit Sources</h4>
                <Row className="my-1">
                    <Col>
                        <Row>
                            <Col>Title:</Col>
                        </Row>
                        <Row>
                            <Col>{adminForm.mainField('Source', { searchEndpoint: (s) => `../api/source?q=${s}` })}</Col>
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
                        Author (required):
                        <input
                            {...adminForm.form.register('author', { required: 'You must provide an author.' })}
                            type="text"
                            placeholder="Author(s)"
                            className="form-control"
                            disabled={!selected}
                        />
                        {adminForm.form.formState.errors.author && (
                            <span className="text-danger">{adminForm.form.formState.errors.author.message}</span>
                        )}
                    </Col>
                    <Col>
                        Publication Year (required):
                        <input
                            {...adminForm.form.register('pubyear', {
                                required: 'You must provide a valid 4 digit year.',
                                pattern: {
                                    value: /([12][0-9]{3}$)/,
                                    message: 'You must provide a valid 4 digit year.',
                                },
                            })}
                            type="text"
                            placeholder="Pub Year"
                            className="form-control"
                            disabled={!selected}
                        />
                        {adminForm.form.formState.errors.pubyear && (
                            <span className="text-danger">{adminForm.form.formState.errors.pubyear.message}</span>
                        )}
                    </Col>
                </Row>

                <Row className="my-1">
                    <Col>
                        Reference Link (required):
                        <input
                            {...adminForm.form.register('link', { required: 'You must provide a reference link.' })}
                            type="text"
                            placeholder="Link"
                            className="form-control"
                            disabled={!selected}
                        />
                        {adminForm.form.formState.errors.link && (
                            <span className="text-danger">{adminForm.form.formState.errors.link.message}</span>
                        )}
                    </Col>
                </Row>
                <Row className="my-1">
                    <Col>
                        License (required):
                        <select
                            {...adminForm.form.register('license', { required: 'You must choose a license.' })}
                            className="form-control"
                            disabled={!selected}
                        >
                            <option>{ImageLicenseValues.PUBLIC_DOMAIN}</option>
                            <option>{ImageLicenseValues.CC_BY}</option>
                            <option>{ImageLicenseValues.ALL_RIGHTS}</option>
                        </select>{' '}
                        {adminForm.form.formState.errors.license && (
                            <span className="text-danger">{adminForm.form.formState.errors.license.message}</span>
                        )}
                    </Col>
                </Row>
                <Row className="my-1">
                    <Col>
                        License Link:
                        <input
                            {...adminForm.form.register('licenselink', {
                                validate: (v) =>
                                    !(adminForm.form.getValues('license') === ImageLicenseValues.CC_BY && (!v || v.length < 1)) ||
                                    'When using the CC BY license, you must provide a link to the license.',
                            })}
                            type="text"
                            placeholder="License Link"
                            className="form-control"
                            disabled={!selected}
                        />
                        {adminForm.form.formState.errors.licenselink && (
                            <span className="text-danger">{adminForm.form.formState.errors.licenselink.message}</span>
                        )}
                    </Col>
                </Row>
                <Row className="my-1">
                    <Col>
                        <p>
                            Citation (required) (
                            <a href="https://www.mybib.com/tools/mla-citation-generator" target="_blank" rel="noreferrer">
                                MLA Form
                            </a>
                            ):
                        </p>
                        <textarea
                            {...adminForm.form.register('citation', { required: 'You must provide a citation in MLA form.' })}
                            placeholder="Citation"
                            className="form-control"
                            rows={8}
                            disabled={!selected}
                        />
                        {adminForm.form.formState.errors.citation && (
                            <span className="text-danger">{adminForm.form.formState.errors.citation.message}</span>
                        )}
                    </Col>
                </Row>
                <Row className="formGroup pb-1">
                    <Col className="me-auto">
                        <input
                            {...adminForm.form.register('datacomplete')}
                            type="checkbox"
                            className="form-input-checkbox"
                            disabled={!selected}
                        />{' '}
                        All information from this Source has been input into the database?
                    </Col>
                </Row>
            </>
        </Admin>
    );
};

export const getServerSideProps: GetServerSideProps = async (context: { query: ParsedUrlQuery }) => {
    const queryParam = 'id';
    const id = pipe(extractQueryParam(context.query, queryParam), O.getOrElse(constant('')));
    return {
        props: {
            id: id,
            sources: await mightFailWithArray<SourceApi>()(allSources()),
        },
    };
};

export default Source;
