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
import { GlossaryEntryUpsertFields } from '../../libs/api/apitypes';
import { allGlossaryEntries, Entry } from '../../libs/db/glossary';
import Admin from '../../libs/pages/admin';
import { mightFailWithArray } from '../../libs/utils/util';

const schema = yup.object().shape({
    value: yup.mixed().required(),
    definition: yup.string().required(),
    urls: yup.string().required(),
});

type Props = {
    id: string;
    glossary: Entry[];
};

type FormFields = AdminFormFields<Entry> & Pick<Entry, 'definition' | 'urls'>;

const updateEntry = (s: Entry, newValue: string): Entry => ({
    ...s,
    word: newValue,
});

const convertToFields = (s: Entry): FormFields => ({
    ...s,
    del: false,
    value: [s],
});

// eslint-disable-next-line @typescript-eslint/no-unused-vars
const toUpsertFields = (fields: FormFields, word: string, id: number): GlossaryEntryUpsertFields => {
    return {
        ...fields,
        word: word,
    };
};

const emptyForm = {
    value: [],
    defintion: '',
};

const Glossary = ({ id, glossary }: Props): JSX.Element => {
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
        'Glossary',
        id,
        glossary,
        updateEntry,
        convertToFields,
        toUpsertFields,
        { keyProp: 'word', delEndpoint: '../api/glossary/', upsertEndpoint: '../api/glossary/upsert' },
        schema,
        emptyForm,
    );

    const router = useRouter();

    const onSubmit = async (fields: FormFields) => {
        formSubmit(fields);
    };

    return (
        <Admin
            type="Glossary"
            keyField="word"
            editName={{ getDefault: () => selected?.word, renameCallback: renameCallback(onSubmit) }}
            setShowModal={setShowModal}
            showModal={showModal}
            setError={setError}
            error={error}
            setDeleteResults={setDeleteResults}
            deleteResults={deleteResults}
        >
            <form onSubmit={form.handleSubmit(onSubmit)} className="m-4 pr-4">
                <h4>Add/Edit Glossary Entries</h4>
                <Row className="form-group">
                    <Col>
                        <Row>
                            <Col>Word:</Col>
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
                                            setSelected(e[0]);
                                            router.replace(`?id=${e[0].id}`, undefined, { shallow: true });
                                        }
                                    }}
                                    placeholder="Word"
                                    options={data}
                                    labelKey={'word'}
                                    clearButton
                                    isInvalid={!!form.errors.value}
                                    newSelectionPrefix="Add a new Word: "
                                    allowNew={true}
                                />
                                {form.errors.value && <span className="text-danger">The Word is required.</span>}
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
                        Definition:
                        <textarea name="definition" className="form-control" ref={form.register} rows={4} />
                        {form.errors.definition && <span className="text-danger">You must provide the defintion.</span>}
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        URLs (separated by a newline [enter]):
                        <textarea name="urls" className="form-control" ref={form.register} rows={3} />
                    </Col>
                </Row>
                <Row className="fromGroup" hidden={!selected}>
                    <Col xs="1">Delete?:</Col>
                    <Col className="mr-auto">
                        <input name="del" type="checkbox" className="form-check-input" ref={form.register} />
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
            glossary: await mightFailWithArray<Entry>()(allGlossaryEntries()),
        },
    };
};
export default Glossary;
