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
import { SourceApi, SourceUpsertFields } from '../../libs/api/apitypes';
import { allSources } from '../../libs/db/source';
import Admin from '../../libs/pages/admin';
import { mightFailWithArray } from '../../libs/utils/util';

const schema = yup.object().shape({
    value: yup.mixed().required(),
    author: yup.string().required(),
    pubyear: yup.string().matches(/([12][0-9]{3})/),
    citation: yup.string().required(),
});

type Props = {
    id: string;
    sources: SourceApi[];
};

type FormFields = AdminFormFields<SourceApi> & Omit<SourceApi, 'id' | 'title'>;

const updateSource = (s: SourceApi, newValue: string) => ({
    ...s,
    title: newValue,
});

// eslint-disable-next-line @typescript-eslint/no-unused-vars
const toUpsertFields = (fields: FormFields, name: string, id: number): SourceUpsertFields => {
    return {
        ...fields,
        title: name,
    };
};

const updatedFormFields = async (s: SourceApi | undefined): Promise<FormFields> => {
    if (s != undefined) {
        return {
            ...s,
            del: false,
            value: [s],
        };
    }

    return {
        value: [],
        author: '',
        pubyear: '',
        link: '',
        citation: '',
        del: false,
    };
};

const Source = ({ id, sources }: Props): JSX.Element => {
    const {
        data,
        selected,
        setSelected,
        showRenameModal: showModal,
        setShowRenameModal: setShowModal,
        error,
        setError,
        deleteResults,
        setDeleteResults,
        renameCallback,
        form,
        formSubmit,
    } = useAdmin(
        'Source',
        id,
        sources,
        updateSource,
        toUpsertFields,
        { keyProp: 'title', delEndpoint: '../api/source/', upsertEndpoint: '../api/source/upsert' },
        schema,
        updatedFormFields,
    );

    const router = useRouter();

    return (
        <Admin
            type="Source"
            keyField="title"
            editName={{ getDefault: () => selected?.title, renameCallback: renameCallback(formSubmit) }}
            setShowModal={setShowModal}
            showModal={showModal}
            setError={setError}
            error={error}
            setDeleteResults={setDeleteResults}
            deleteResults={deleteResults}
        >
            <form onSubmit={form.handleSubmit(formSubmit)} className="m-4 pr-4">
                <h4>Add/Edit Sources</h4>
                <Row className="form-group">
                    <Col>
                        <Row>
                            <Col>Title:</Col>
                        </Row>
                        <Row>
                            <Col>
                                <ControlledTypeahead
                                    control={form.control}
                                    name="value"
                                    onChangeWithNew={(e, isNew) => {
                                        if (isNew || !e[0]) {
                                            setSelected(undefined);
                                            router.replace(``, undefined, { shallow: true });
                                        } else {
                                            const source: SourceApi = e[0];
                                            setSelected(source);
                                            router.replace(`?id=${source.id}`, undefined, { shallow: true });
                                        }
                                    }}
                                    placeholder="Title"
                                    options={data}
                                    labelKey="title"
                                    clearButton
                                    isInvalid={!!form.errors.value}
                                    newSelectionPrefix="Add a new Source: "
                                    allowNew={true}
                                />
                                {form.errors.value && <span className="text-danger">The Title is required.</span>}
                            </Col>
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
                        <input type="text" placeholder="Author(s)" name="author" className="form-control" ref={form.register} />
                        {form.errors.author && <span className="text-danger">You must provide an author.</span>}
                    </Col>
                    <Col>
                        Publication Year:
                        <input type="text" placeholder="Pub Year" name="pubyear" className="form-control" ref={form.register} />
                        {form.errors.pubyear && <span className="text-danger">You must provide a valid 4 digit year.</span>}
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        Reference Link:
                        <input type="text" placeholder="Link" name="link" className="form-control" ref={form.register} />
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
                        <textarea name="citation" placeholder="Citation" className="form-control" ref={form.register} rows={8} />
                        {form.errors.citation && <span className="text-danger">You must provide a citation in MLA form.</span>}
                    </Col>
                </Row>
                <Row className="fromGroup" hidden={!selected}>
                    <Col xs="1">Delete?:</Col>
                    <Col className="mr-auto">
                        <input name="del" type="checkbox" className="form-check-input" ref={form.register} />
                    </Col>
                </Row>
                <Row className="formGroup">
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
            sources: await mightFailWithArray<SourceApi>()(allSources()),
        },
    };
};

export default Source;
