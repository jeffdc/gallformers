import { yupResolver } from '@hookform/resolvers/yup';
import * as O from 'fp-ts/lib/Option';
import { constant, pipe } from 'fp-ts/lib/function';
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
import { DeleteResult, SourceApi, SourceUpsertFields } from '../../libs/api/apitypes';
import { allSources } from '../../libs/db/source';
import { mightFailWithArray } from '../../libs/utils/util';

const Schema = yup.object().shape({
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

const Source = (props: Props): JSX.Element => {
    const { register, handleSubmit, errors, control, setValue, reset } = useForm<FormFields>({
        mode: 'onBlur',
        resolver: yupResolver(Schema),
    });
    const [existingId, setExistingId] = useState<number | undefined>(
        props.id && props.id !== '' ? parseInt(props.id) : undefined,
    );
    const [deleteResults, setDeleteResults] = useState<DeleteResult>();
    const [sources, setSources] = useState(props.sources);
    const [error, setError] = useState('');

    const router = useRouter();
    const { doDeleteOrUpsert } = useAPIs<SourceApi, SourceUpsertFields>('title', '../api/source/', '../api/source/upsert');

    const onFamilyChange = useCallback(
        (id: number | undefined) => {
            if (id == undefined) {
                setValue('value', []);
                setValue('author', '');
                setValue('pubyear', '');
                setValue('link', '');
                setValue('citation', '');
            } else {
                try {
                    const source = sources.find((s) => s.id === id);
                    if (source == undefined) {
                        throw new Error(`Somehow we have a source selection that does not exist?! sourceid: ${id}`);
                    }
                    setValue('value', [source]);
                    setValue('author', source.author);
                    setValue('pubyear', source.pubyear);
                    setValue('link', source.link);
                    setValue('citation', source.citation);
                } catch (e) {
                    console.error(e);
                    setError(e);
                }
            }
        },
        [sources, setValue],
    );

    useEffect(() => {
        onFamilyChange(existingId);
    }, [existingId, onFamilyChange]);

    const onSubmit = async (data: FormFields) => {
        const postDelete = (id: number | string, result: DeleteResult) => {
            setSources(sources.filter((s) => s.id !== id));
            setDeleteResults(result);
        };

        const postUpdate = (res: Response) => {
            router.push(res.url);
        };

        const convertFormFieldsToUpsert = (fields: FormFields, title: string, id: number): SourceUpsertFields => ({
            ...fields,
            title: title,
        });

        await doDeleteOrUpsert(data, postDelete, postUpdate, convertFormFieldsToUpsert)
            .then(() => reset())
            .catch((e: unknown) => setError(`Failed to save changes. ${e}.`));
    };

    return (
        <Auth>
            <>
                <Head>
                    <title>Add/Edit Sources</title>
                </Head>

                {error.length > 0 && (
                    <Alert variant="danger" onClose={() => setError('')} dismissible>
                        <Alert.Heading>Uh-oh</Alert.Heading>
                        <p>{error}</p>
                    </Alert>
                )}

                <form onSubmit={handleSubmit(onSubmit)} className="m-4 pr-4">
                    <h4>Add/Edit Sources</h4>
                    <Row className="form-group">
                        <Col>
                            Title:
                            <ControlledTypeahead
                                control={control}
                                name="value"
                                onChangeWithNew={(e, isNew) => {
                                    if (isNew || !e[0]) {
                                        setExistingId(undefined);
                                        router.replace(``, undefined, { shallow: true });
                                    } else {
                                        const source: SourceApi = e[0];
                                        setExistingId(source.id);
                                        router.replace(`?id=${source.id}`, undefined, { shallow: true });
                                    }
                                }}
                                placeholder="Title"
                                options={sources}
                                labelKey="title"
                                clearButton
                                isInvalid={!!errors.value}
                                newSelectionPrefix="Add a new Source: "
                                allowNew={true}
                            />
                            {errors.value && <span className="text-danger">The Title is required.</span>}
                        </Col>
                    </Row>
                    <Row className="form-group">
                        <Col>
                            Author:
                            <input type="text" placeholder="Author(s)" name="author" className="form-control" ref={register} />
                            {errors.author && <span className="text-danger">You must provide an author.</span>}
                        </Col>
                        <Col>
                            Publication Year:
                            <input type="text" placeholder="Pub Year" name="pubyear" className="form-control" ref={register} />
                            {errors.pubyear && <span className="text-danger">You must provide a valid 4 digit year.</span>}
                        </Col>
                    </Row>
                    <Row className="form-group">
                        <Col>
                            Reference Link:
                            <input type="text" placeholder="Link" name="link" className="form-control" ref={register} />
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
                            <input type="text" placeholder="Citation" name="citation" className="form-control" ref={register} />
                            {errors.citation && <span className="text-danger">You must provide a citation in MLA form.</span>}
                        </Col>
                    </Row>
                    <Row className="fromGroup" hidden={!existingId}>
                        <Col xs="1">Delete?:</Col>
                        <Col className="mr-auto">
                            <input name="del" type="checkbox" className="form-check-input" ref={register} />
                        </Col>
                    </Row>
                    <Row className="formGroup">
                        <Col>
                            <input type="submit" className="button" value="Submit" />
                        </Col>
                    </Row>
                    <Row hidden={!deleteResults}>
                        <Col>{`Deleted ${deleteResults?.name}.`}</Col>
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
            sources: await mightFailWithArray<SourceApi>()(allSources()),
        },
    };
};

export default Source;
