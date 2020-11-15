import { yupResolver } from '@hookform/resolvers/yup';
import { useRouter } from 'next/router';
import React from 'react';
import { Col, Row } from 'react-bootstrap';
import { useForm } from 'react-hook-form';
import * as yup from 'yup';
import Auth from '../../components/auth';
import { SpeciesUpsertFields } from '../../libs/apitypes';

const Schema = yup.object().shape({
    title: yup.string().required(),
    author: yup.string().required(),
    pubyear: yup.string().matches(/([12][0-9]{3})/),
    link: yup.string().url().required(),
    citation: yup.string().required(),
});

const Host = (): JSX.Element => {
    const { register, handleSubmit, errors } = useForm({
        mode: 'onBlur',
        resolver: yupResolver(Schema),
    });

    const router = useRouter();

    const onSubmit = async (data: SpeciesUpsertFields) => {
        try {
            const res = await fetch('../api/source/upsert', {
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
        } catch (e) {
            console.log(e);
        }
    };

    return (
        <Auth>
            <form onSubmit={handleSubmit(onSubmit)} className="m-4 pr-4">
                <h4>Add A Source</h4>
                <Row className="form-group">
                    <Col>
                        Title:
                        <input type="text" placeholder="Title" name="title" className="form-control" ref={register} />
                        {errors.title && <span className="text-danger">The Title is required.</span>}
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
                        {errors.link && <span className="text-danger">You must provide a valid URL link.</span>}
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        <p>
                            Citation (<a href="https://www.mybib.com/tools/mla-citation-generator">MLA Form</a>):
                        </p>
                        <input type="text" placeholder="Citation" name="citation" className="form-control" ref={register} />
                        {errors.citation && <span className="text-danger">You must provide a citation in MLA form.</span>}
                    </Col>
                </Row>
                <input type="submit" className="button" />
            </form>
        </Auth>
    );
};

export default Host;
