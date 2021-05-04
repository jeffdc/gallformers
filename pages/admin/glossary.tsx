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
import { GlossaryEntryUpsertFields } from '../../libs/api/apitypes';
import { allGlossaryEntries, Entry } from '../../libs/db/glossary';
import Admin from '../../libs/pages/admin';
import { mightFailWithArray } from '../../libs/utils/util';

const schema = yup.object().shape({
    mainField: yup.mixed().required(),
    definition: yup.string().required(),
    urls: yup.string().required(),
});

type Props = {
    id: string;
    glossary: Entry[];
};

type FormFields = AdminFormFields<Entry> & Pick<Entry, 'definition' | 'urls'>;

const renameEntry = async (s: Entry, e: RenameEvent): Promise<Entry> => ({
    ...s,
    word: e.new,
});

const toUpsertFields = (fields: FormFields, word: string, id: number): GlossaryEntryUpsertFields => {
    return {
        ...fields,
        id: id,
        word: word,
    };
};

const updatedFormFields = async (e: Entry | undefined): Promise<FormFields> => {
    if (e != undefined) {
        return {
            mainField: [e],
            definition: e.definition,
            urls: e.urls,
            del: false,
        };
    }

    return {
        mainField: [],
        definition: '',
        urls: '',
        del: false,
    };
};

const createNewEntry = (word: string): Entry => ({
    word: word,
    definition: '',
    urls: '',
    id: -1,
});

const Glossary = ({ id, glossary }: Props): JSX.Element => {
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
        'Glossary Entry',
        id,
        glossary,
        renameEntry,
        toUpsertFields,
        { keyProp: 'word', delEndpoint: '../api/glossary/', upsertEndpoint: '../api/glossary/upsert' },
        schema,
        updatedFormFields,
        createNewEntry,
    );

    return (
        <Admin
            type="Glossary"
            keyField="word"
            editName={{ getDefault: () => selected?.word, renameCallback: renameCallback }}
            setShowModal={setShowModal}
            showModal={showModal}
            setError={setError}
            error={error}
            setDeleteResults={setDeleteResults}
            deleteResults={deleteResults}
            selected={selected}
        >
            <form onSubmit={form.handleSubmit(formSubmit)} className="m-4 pr-4">
                <h4>Add/Edit Glossary Entries</h4>
                <Row className="form-group">
                    <Col>
                        <Row>
                            <Col>Word:</Col>
                        </Row>
                        <Row>
                            <Col>{mainField('word', 'Word')}</Col>
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
                        <textarea {...form.register('definition')} className="form-control" rows={4} />
                        {form.formState.errors.definition && <span className="text-danger">You must provide the defintion.</span>}
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        URLs (separated by a newline [enter]):
                        <textarea {...form.register('urls')} className="form-control" rows={3} />
                        {form.formState.errors.urls && (
                            <span className="text-danger">You must provide a URL for the source of the defintion.</span>
                        )}
                    </Col>
                </Row>
                <Row className="form-input">
                    <Col>
                        <input type="submit" className="button" value="Submit" />
                    </Col>
                    <Col>{deleteButton('Caution. The glossary entry will deleted.')}</Col>
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
