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
import { ALLRIGHTS, CC0, CCBY, SourceApi, SourceUpsertFields } from '../../libs/api/apitypes';
import { allSources } from '../../libs/db/source';
import Admin from '../../libs/pages/admin';
import { mightFailWithArray } from '../../libs/utils/util';

const schema = yup.object().shape({
    mainField: yup.mixed().required(),
    author: yup.string().required(),
    pubyear: yup.string().matches(/([12][0-9]{3})/),
    citation: yup.string().required(),
    license: yup.string().required('You must select a license.'),
    licenselink: yup
        .string()
        .url('The link must be a valid URL.')
        .when('license', {
            is: (l: string) => l === CCBY,
            then: yup.string().url().required('The CC-BY license requires that you provide a link to the license.'),
        }),
});

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

const Source = ({ id, sources }: Props): JSX.Element => {
    const {
        selected,
        showRenameModal: showModal,
        setShowRenameModal: setShowModal,
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
        'Source',
        id,
        sources,
        renameSource,
        toUpsertFields,
        { keyProp: 'title', delEndpoint: '../api/source/', upsertEndpoint: '../api/source/upsert' },
        schema,
        updatedFormFields,
        false,
        createNewSource,
    );

    return (
        <Admin
            type="Source"
            keyField="title"
            editName={{ getDefault: () => selected?.title, renameCallback: renameCallback }}
            setShowModal={setShowModal}
            showModal={showModal}
            setError={setError}
            error={error}
            setDeleteResults={setDeleteResults}
            deleteResults={deleteResults}
            selected={selected}
        >
            <form onSubmit={form.handleSubmit(formSubmit)} className="m-4 pr-4">
                <h4>Add/Edit Sources</h4>
                <Row className="form-group">
                    <Col>
                        <Row>
                            <Col>Title:</Col>
                        </Row>
                        <Row>
                            <Col>{mainField('title', 'Source')}</Col>
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
                        Author:
                        <input {...form.register('author')} type="text" placeholder="Author(s)" className="form-control" />
                        {form.formState.errors.author && <span className="text-danger">You must provide an author.</span>}
                    </Col>
                    <Col>
                        Publication Year:
                        <input {...form.register('pubyear')} type="text" placeholder="Pub Year" className="form-control" />
                        {form.formState.errors.pubyear && (
                            <span className="text-danger">You must provide a valid 4 digit year.</span>
                        )}
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        Reference Link:
                        <input {...form.register('link')} type="text" placeholder="Link" className="form-control" />
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        License:
                        <select {...form.register('license')} className="form-control">
                            <option>{CC0}</option>
                            <option>{CCBY}</option>
                            <option>{ALLRIGHTS}</option>
                        </select>{' '}
                        {form.formState.errors.license && (
                            <span className="text-danger">{form.formState.errors.license.message}</span>
                        )}
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        License Link:
                        <input
                            {...form.register('licenselink')}
                            type="text"
                            placeholder="License Link"
                            className="form-control"
                        />
                        {form.formState.errors.licenselink && (
                            <span className="text-danger">{form.formState.errors.licenselink.message}</span>
                        )}
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        <p>
                            Citation (
                            <a href="https://www.mybib.com/tools/mla-citation-generator" target="_blank" rel="noreferrer">
                                MLA Form
                            </a>
                            ):
                        </p>
                        <textarea {...form.register('citation')} placeholder="Citation" className="form-control" rows={8} />
                        {form.formState.errors.citation && (
                            <span className="text-danger">You must provide a citation in MLA form.</span>
                        )}
                    </Col>
                </Row>
                <Row className="formGroup pb-1">
                    <Col className="mr-auto">
                        <input {...form.register('datacomplete')} type="checkbox" className="form-input-checkbox" /> All
                        information from this Source has been input into the database?
                    </Col>
                </Row>

                <Row className="formGroup">
                    <Col>
                        <input type="submit" className="button" value="Submit" disabled={!selected} />
                    </Col>
                    <Col>{deleteButton('Caution. All data associated with this Source will be deleted.')}</Col>
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
            sources: await mightFailWithArray<SourceApi>()(allSources()),
        },
    };
};

export default Source;
