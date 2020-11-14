import { yupResolver } from '@hookform/resolvers/yup';
import { useRouter } from 'next/router';
import React from 'react';
import { Col, Row } from 'react-bootstrap';
import { useForm } from 'react-hook-form';
import * as yup from 'yup';
import Auth from '../../components/auth';
import { FamilyUpsertFields } from '../../libs/apitypes';
import { genOptions } from '../../libs/utils/forms';

const Schema = yup.object().shape({
    name: yup.string().required(),
    description: yup.string().required(),
});

const Family = (): JSX.Element => {
    const { register, handleSubmit, errors } = useForm({
        mode: 'onBlur',
        resolver: yupResolver(Schema),
    });

    const router = useRouter();

    const onSubmit = async (data: FamilyUpsertFields) => {
        try {
            const res = await fetch('../api/family/upsert', {
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
                        Name:
                        <input type="text" placeholder="Name" name="name" className="form-control" ref={register} />
                        {errors.name && <span className="text-danger">The Name is required.</span>}
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        Description:
                        <select name="description" className="form-control" ref={register}>
                            {genOptions(['Beetle', 'Fly', 'Midge', 'Mite', 'Moth', 'Plant', 'Scale', 'Wasp'])}
                        </select>
                        {errors.description && <span className="text-danger">You must provide the description.</span>}
                    </Col>
                </Row>
                <input type="submit" className="button" />
            </form>
        </Auth>
    );
};

export default Family;
