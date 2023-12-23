import { constant, pipe } from 'fp-ts/lib/function.js';
import * as O from 'fp-ts/lib/Option.js';
import { GetServerSideProps } from 'next';
import { ParsedUrlQuery } from 'querystring';
import { Button, Col, Row } from 'react-bootstrap';
import { RenameEvent } from '../../components/editname.js';
import useAdmin from '../../hooks/useadmin.js';
import { AdminFormFields, adminFormFieldsSchema } from '../../hooks/useAPIs.js';
import { extractQueryParam } from '../../libs/api/apipage.js';
import { Entry, EntrySchema, GlossaryEntryUpsertFields } from '../../libs/api/apitypes.js';
import { allGlossaryEntries } from '../../libs/db/glossary.js';
import Admin from '../../libs/pages/admin.js';
import { mightFailWithArray } from '../../libs/utils/util.js';
import * as t from 'io-ts';

const schema = t.intersection([adminFormFieldsSchema(EntrySchema), EntrySchema]);
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

const Glossary = ({ id, glossary }: Props): JSX.Element => {
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
        'Glossary Entry',
        id,
        renameEntry,
        toUpsertFields,
        {
            keyProp: 'word',
            delEndpoint: '../api/glossary/',
            upsertEndpoint: '../api/glossary/upsert',
            nameExistsEndpoint: (s: string) => `/api/glossary?name=${s}`,
        },
        schema,
        updatedFormFields,
        false,
        createNewEntry,
        glossary,
    );

    return (
        <Admin
            type="Glossary"
            keyField="word"
            editName={{ getDefault: () => selected?.word, renameCallback: renameCallback, nameExistsCallback: nameExists }}
            setShowModal={setShowModal}
            showModal={showModal}
            setError={setError}
            error={error}
            setDeleteResults={setDeleteResults}
            deleteResults={deleteResults}
            selected={selected}
        >
            <form onSubmit={form.handleSubmit(formSubmit)} className="m-4 pe-4">
                <h4>Add/Edit Glossary Entries</h4>
                <Row className="my-1">
                    <Col>
                        <Row>
                            <Col>Word (unless it is a proper name, use lower case):</Col>
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
                <Row className="my-1">
                    <Col>
                        Definition (required):
                        <textarea {...form.register('definition')} className="form-control" rows={4} disabled={!selected} />
                        {form.formState.errors.definition && (
                            <span className="text-danger">You must provide the definition.</span>
                        )}
                    </Col>
                </Row>
                <Row className="my-1">
                    <Col>
                        URLs (required) (separated by a newline [enter]):
                        <textarea {...form.register('urls')} className="form-control" rows={3} disabled={!selected} />
                        {form.formState.errors.urls && (
                            <span className="text-danger">You must provide a URL for the source of the definition.</span>
                        )}
                    </Col>
                </Row>
                <Row className="my-1">
                    <Col>
                        <input type="submit" className="button" value="Submit" disabled={!selected || !isValid} />
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
    const id = pipe(extractQueryParam(context.query, queryParam), O.getOrElse(constant('')));
    return {
        props: {
            id: id,
            glossary: await mightFailWithArray<Entry>()(allGlossaryEntries()),
        },
    };
};
export default Glossary;
