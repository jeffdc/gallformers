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

const renameEntry = (s: Entry, e: RenameEvent): Promise<Entry> =>
    Promise.resolve({
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

const updatedFormFields = (e: Entry | undefined): Promise<FormFields> => {
    if (e != undefined) {
        return Promise.resolve({
            mainField: [e],
            definition: e.definition,
            urls: e.urls,
            del: false,
        });
    }

    return Promise.resolve({
        mainField: [],
        definition: '',
        urls: '',
        del: false,
    });
};

const createNewEntry = (word: string): Entry => ({
    word: word,
    definition: '',
    urls: '',
    id: -1,
});

const keyFieldName = 'word';

const Glossary = ({ id, glossary }: Props): JSX.Element => {
    const adminForm = useAdmin(
        'Glossary Entry',
        keyFieldName,
        id,
        renameEntry,
        toUpsertFields,
        {
            delEndpoint: '../api/glossary/',
            upsertEndpoint: '../api/glossary/upsert',
            nameExistsEndpoint: (s: string) => `/api/glossary/word/${s}`,
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
            editName={{
                getDefault: () => adminForm.selected?.word,
                renameCallback: adminForm.renameCallback,
                nameExistsCallback: adminForm.nameExists,
            }}
            selected={adminForm.selected}
            {...adminForm}
            deleteButton={adminForm.deleteButton('Caution. The glossary entry will be PERMANENTLY deleted.', false)}
            saveButton={adminForm.saveButton()}
        >
            <>
                <h4>Add/Edit Glossary Entries</h4>

                <Row className="my-1">
                    <Col>
                        <Row>
                            <Col>Word (unless it is a proper name, use lower case):</Col>
                        </Row>
                        <Row>
                            <Col>{adminForm.mainField('Word')}</Col>
                            {adminForm.selected && (
                                <Col xs={1}>
                                    <Button
                                        variant="secondary"
                                        className="btn-sm"
                                        onClick={() => {
                                            adminForm.setShowRenameModal(true);
                                        }}
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
                        Definition (required):
                        <textarea
                            {...adminForm.form.register('definition', {
                                required: 'You must provide a definition',
                                disabled: !adminForm.selected,
                            })}
                            className="form-control"
                            rows={4}
                        />
                        {adminForm.form.formState.errors.definition && (
                            <span className="text-danger">{adminForm.errors.definition?.message}</span>
                        )}
                    </Col>
                </Row>
                <Row className="my-1">
                    <Col>
                        URLs (required) (separated by a newline [enter]):
                        <textarea
                            {...adminForm.form.register('urls', {
                                required: 'You must provide at least one URL that is the source of the definition.',
                                disabled: !adminForm.selected,
                            })}
                            className="form-control"
                            rows={3}
                        />
                        {adminForm.form.formState.errors.urls && (
                            <span className="text-danger">{adminForm.errors.urls?.message}</span>
                        )}
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
            glossary: await mightFailWithArray<Entry>()(allGlossaryEntries()),
        },
    };
};
export default Glossary;
