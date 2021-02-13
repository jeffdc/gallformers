import { yupResolver } from '@hookform/resolvers/yup';
import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetServerSideProps } from 'next';
import Head from 'next/head';
import { useRouter } from 'next/router';
import { ParsedUrlQuery } from 'querystring';
import React, { useCallback, useEffect, useState } from 'react';
import { Alert, Col, Row } from 'react-bootstrap';
import { useForm } from 'react-hook-form';
import * as yup from 'yup';
import Auth from '../../components/auth';
import ControlledTypeahead from '../../components/controlledtypeahead';
import { AdminFormFields, useAPIs } from '../../hooks/useAPIs';
import { extractQueryParam } from '../../libs/api/apipage';
import { DeleteResult, GlossaryEntryUpsertFields } from '../../libs/api/apitypes';
import { allGlossaryEntries, Entry } from '../../libs/db/glossary';
import { mightFailWithArray } from '../../libs/utils/util';

const Schema = yup.object().shape({
    value: yup.mixed().required(),
    definition: yup.string().required(),
    urls: yup.string().required(),
});

type Props = {
    id: string;
    glossary: Entry[];
};

type FormFields = AdminFormFields<Entry> & Pick<Entry, 'definition' | 'urls'>;

const Glossary = (props: Props): JSX.Element => {
    if (!props.glossary) throw new Error(`The input props for glossary edit can not be null or undefined.`);

    const [existingId, setExistingId] = useState<number | undefined>(
        props.id && props.id !== '' ? parseInt(props.id) : undefined,
    );
    const [deleteResults, setDeleteResults] = useState<DeleteResult>();
    const [glossary, setGlossary] = useState(props.glossary);
    const [error, setError] = useState('');

    const { register, handleSubmit, errors, control, setValue, reset } = useForm<FormFields>({
        mode: 'onBlur',
        resolver: yupResolver(Schema),
    });

    const { doDeleteOrUpsert } = useAPIs<Entry, GlossaryEntryUpsertFields>('word', '../api/glossary/', '../api/glossary/upsert');

    const router = useRouter();

    const onGlossaryChange = useCallback(
        (id: number | undefined) => {
            if (id == undefined) {
                setValue('value', []);
                setValue('definition', '');
                setValue('urls', '');
            } else {
                try {
                    const glos = props.glossary.find((g) => g.id === id);
                    if (glos == undefined) {
                        throw new Error(`Somehow we have a family selection that does not exist?! familyid: ${id}`);
                    }

                    setValue('value', [glos]);
                    setValue('definition', glos.definition);
                    setValue('urls', glos.urls);
                } catch (e) {
                    console.error(e);
                    setError(e);
                }
            }
        },
        [props.glossary, setValue],
    );

    useEffect(() => {
        onGlossaryChange(existingId);
    }, [existingId, onGlossaryChange]);

    const onSubmit = async (data: FormFields) => {
        const postDelete = (id: number | string, result: DeleteResult) => {
            setGlossary(glossary.filter((g) => g.id !== id));
            setDeleteResults(result);
        };

        const postUpdate = (res: Response) => {
            router.push(res.url);
        };

        const convertFormFieldsToUpsert = (fields: FormFields, word: string, id: number): GlossaryEntryUpsertFields => ({
            ...fields,
            word: word,
        });

        await doDeleteOrUpsert(data, postDelete, postUpdate, convertFormFieldsToUpsert)
            .then(() => reset())
            .catch((e) => setError(`Failed to save changes. ${e}.`));
    };

    return (
        <Auth>
            <>
                <Head>
                    <title>Add/Edit Glossary Entries</title>
                </Head>

                {error.length > 0 && (
                    <Alert variant="danger" onClose={() => setError('')} dismissible>
                        <Alert.Heading>Uh-oh</Alert.Heading>
                        <p>{error}</p>
                    </Alert>
                )}

                <form onSubmit={handleSubmit(onSubmit)} className="m-4 pr-4">
                    <h4>Add/Edit Glossary Entries</h4>
                    <Row className="form-group">
                        <Col>
                            Name:
                            <ControlledTypeahead
                                control={control}
                                name="value"
                                onChangeWithNew={(e, isNew) => {
                                    if (isNew || !e[0]) {
                                        setExistingId(undefined);
                                        router.replace(``, undefined, { shallow: true });
                                    } else {
                                        const entry: Entry = e[0];
                                        setExistingId(entry.id);
                                        router.replace(`?id=${e[0].id}`, undefined, { shallow: true });
                                    }
                                }}
                                placeholder="Word"
                                options={glossary}
                                labelKey={'word'}
                                clearButton
                                isInvalid={!!errors.value}
                                newSelectionPrefix="Add a new Word: "
                                allowNew={true}
                            />
                            {errors.value && <span className="text-danger">The Word is required.</span>}
                        </Col>
                    </Row>
                    <Row className="form-group">
                        <Col>
                            Definition:
                            <textarea name="definition" className="form-control" ref={register} rows={4} />
                            {errors.definition && <span className="text-danger">You must provide the defintion.</span>}
                        </Col>
                    </Row>
                    <Row className="form-group">
                        <Col>
                            URLs (separated by a newline [enter]):
                            <textarea name="urls" className="form-control" ref={register} rows={3} />
                        </Col>
                    </Row>
                    <Row className="fromGroup" hidden={!existingId}>
                        <Col xs="1">Delete?:</Col>
                        <Col className="mr-auto">
                            <input name="del" type="checkbox" className="form-check-input" ref={register} />
                        </Col>
                    </Row>
                    <Row className="form-input">
                        <Col>
                            <input type="submit" className="button" value="Submit" />
                        </Col>
                    </Row>
                    <Row hidden={!deleteResults}>
                        <Col>{`Deleted ${deleteResults?.name}.`}</Col>☹️
                    </Row>
                </form>
            </>
        </Auth>
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
