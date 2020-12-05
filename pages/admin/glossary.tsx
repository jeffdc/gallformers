import { yupResolver } from '@hookform/resolvers/yup';
import { GetServerSideProps } from 'next';
import { useRouter } from 'next/router';
import React, { useState } from 'react';
import { Col, Row } from 'react-bootstrap';
import { useForm } from 'react-hook-form';
import * as yup from 'yup';
import Auth from '../../components/auth';
import ControlledTypeahead from '../../components/controlledtypeahead';
import { DeleteResult, GlossaryEntryUpsertFields } from '../../libs/apitypes';
import { allGlossaryEntries, Entry } from '../../libs/db/glossary';
import { mightFail } from '../../libs/utils/util';

const Schema = yup.object().shape({
    word: yup.string().required(),
    definition: yup.string().required(),
    urls: yup.string().required(),
});

type Props = {
    glossary: Entry[];
};

const Glossary = ({ glossary }: Props): JSX.Element => {
    if (!glossary) throw new Error(`The input props for glossary edit can not be null or undefined.`);

    const [existing, setExisting] = useState(false);
    const [deleteResults, setDeleteResults] = useState<DeleteResult>();

    const { register, handleSubmit, errors, control, setValue, reset } = useForm({
        mode: 'onBlur',
        resolver: yupResolver(Schema),
    });

    const router = useRouter();

    const onSubmit = async (data: GlossaryEntryUpsertFields) => {
        try {
            if (data.delete) {
                const id = glossary.find((e) => e.word === data.word)?.id;
                const res = await fetch(`../api/glossary/${id}`, {
                    method: 'DELETE',
                });

                if (res.status === 200) {
                    setDeleteResults(await res.json());
                } else {
                    throw new Error(await res.text());
                }
            } else {
                const res = await fetch('../api/glossary/upsert', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify(data),
                });

                if (res.status === 200) {
                    router.push(res.url);
                } else {
                    throw new Error(await res.text());
                }
            }
            reset();
        } catch (e) {
            console.log(e);
        }
    };

    return (
        <Auth>
            <form onSubmit={handleSubmit(onSubmit)} className="m-4 pr-4">
                <h4>Add/Modify Glossary Entries</h4>
                <Row className="form-group">
                    <Col>
                        Name:
                        <ControlledTypeahead
                            control={control}
                            name="word"
                            onChange={(e) => {
                                setExisting(false);
                                const f = glossary.find((f) => f.word === e[0]);
                                if (f) {
                                    setExisting(true);
                                    setValue('definition', f.definition);
                                    setValue('urls', f.urls.join('\n'));
                                } else {
                                    setValue('definition', '');
                                    setValue('urls', '');
                                }
                            }}
                            placeholder="Word"
                            options={glossary.map((f) => f.word)}
                            clearButton
                            isInvalid={!!errors.word}
                            newSelectionPrefix="Add a new Word: "
                            allowNew={true}
                        />
                        {errors.word && <span className="text-danger">The Word is required.</span>}
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        Definition:
                        <textarea name="definition" className="form-control" ref={register} rows={4} />
                        {errors.defintion && <span className="text-danger">You must provide the defintion.</span>}
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        URLs (separated by a newline [enter]):
                        <textarea name="urls" className="form-control" ref={register} rows={3} />
                    </Col>
                </Row>
                <Row className="fromGroup" hidden={!existing}>
                    <Col xs="1">Delete?:</Col>
                    <Col className="mr-auto">
                        <input name="delete" type="checkbox" className="form-check-input" ref={register} />
                    </Col>
                </Row>
                <Row className="form-input">
                    <Col>
                        <input type="submit" className="button" />
                    </Col>
                </Row>
                <Row hidden={!deleteResults}>
                    <Col>{`Deleted ${deleteResults?.name}.`}</Col>☹️
                </Row>
            </form>
        </Auth>
    );
};

export const getServerSideProps: GetServerSideProps = async () => {
    return {
        props: {
            glossary: await mightFail(allGlossaryEntries()),
        },
    };
};
export default Glossary;
