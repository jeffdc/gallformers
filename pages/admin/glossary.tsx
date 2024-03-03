import * as O from 'fp-ts/lib/Option';
import { constant, pipe } from 'fp-ts/lib/function';
import { GetServerSideProps } from 'next';
import { ParsedUrlQuery } from 'querystring';
import { Button, Col, Row } from 'react-bootstrap';
import { RenameEvent } from '../../components/editname';
import useAdmin, { AdminFormFields } from '../../hooks/useadmin';
import { extractQueryParam } from '../../libs/api/apipage';
import { Entry, GlossaryEntryUpsertFields } from '../../libs/api/apitypes';
import { allGlossaryEntries } from '../../libs/db/glossary.ts';
import Admin from '../../libs/pages/admin';
import { mightFailWithArray } from '../../libs/utils/util';

type FormFields = AdminFormFields<Entry> & Pick<Entry, 'definition' | 'urls'>;

type Props = {
    id: string;
    glossary: Entry[];
};

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

const keyFieldName = 'word';

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
        nameExists,
        form,
        formSubmit,
        mainField,
        deleteButton,
        saveButton,
    } = useAdmin(
        'Glossary Entry',
        keyFieldName,
        id,
        renameEntry,
        toUpsertFields,
        {
            delEndpoint: '../api/glossary/',
            upsertEndpoint: '../api/glossary/upsert',
            nameExistsEndpoint: (s: string) => `/api/glossary?name=${s}`,
        },
        updatedFormFields,
        false,
        createNewEntry,
        glossary,
    );

    return (
        <Admin
            type="Glossary"
            keyField={keyFieldName}
            editName={{ getDefault: () => selected?.word, renameCallback: renameCallback, nameExistsCallback: nameExists }}
            setShowModal={setShowModal}
            showModal={showModal}
            setError={setError}
            error={error}
            setDeleteResults={setDeleteResults}
            deleteResults={deleteResults}
            selected={selected}
            deleteButton={deleteButton('Caution. The glossary entry will be PERMANENTLY deleted.', false)}
            saveButton={saveButton()}
        >
            <form onSubmit={form.handleSubmit(formSubmit)} className="m-4 pe-4">
                <h4>Add/Edit Glossary Entries</h4>
                <Row className="my-1">
                    <Col>
                        <Row>
                            <Col>Word (unless it is a proper name, use lower case):</Col>
                        </Row>
                        <Row>
                            <Col>{mainField('Word')}</Col>
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
                        Definition (required):
                        <textarea
                            {...form.register('definition', {
                                required: true,
                                disabled: !selected,
                            })}
                            className="form-control"
                            rows={4}
                        />
                        {form.formState.errors.definition && (
                            <span className="text-danger">You must provide the definition.</span>
                        )}
                    </Col>
                </Row>
                <Row className="my-1">
                    <Col>
                        URLs (required) (separated by a newline [enter]):
                        <textarea
                            {...form.register('urls', { required: true, disabled: !selected })}
                            className="form-control"
                            rows={3}
                        />
                        {form.formState.errors.urls && (
                            <span className="text-danger">You must provide a URL for the source of the definition.</span>
                        )}
                    </Col>
                </Row>
            </form>
        </Admin>
    );
};

export const getServerSideProps: GetServerSideProps = async (context: { query: ParsedUrlQuery }) => {
    const queryParam = 'id';
    const id = pipe(extractQueryParam(context.query, queryParam), O.getOrElse(constant('')));
    return {
        props: {
            id: id,
            glossary: await mightFailWithArray<Entry>()(allGlossaryEntries()),
        },
    };
};
export default Glossary;
