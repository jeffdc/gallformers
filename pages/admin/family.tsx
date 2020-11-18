import { yupResolver } from '@hookform/resolvers/yup';
import { family } from '@prisma/client';
import { GetServerSideProps } from 'next';
import { useRouter } from 'next/router';
import React from 'react';
import { Col, Row } from 'react-bootstrap';
import { useForm } from 'react-hook-form';
import * as yup from 'yup';
import Auth from '../../components/auth';
import ControlledTypeahead from '../../components/controlledtypeahead';
import { allFamilies } from '../../libs/db/family';
import { genOptions } from '../../libs/utils/forms';

const Schema = yup.object().shape({
    name: yup.string().required(),
    description: yup.string().required(),
});

type Family = {
    id: number;
    description: string;
};

type Props = {
    families: family[];
};

const Family = ({ families }: Props): JSX.Element => {
    if (!families) throw new Error(`The input props for families can not be null or undefined.`);

    const { register, handleSubmit, errors, control, setValue } = useForm({
        mode: 'onBlur',
        resolver: yupResolver(Schema),
    });

    const router = useRouter();

    const onSubmit = async (data: { name: string; description: string }) => {
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
                <h4>Add A Family</h4>
                <Row className="form-group">
                    <Col>
                        Name:
                        <ControlledTypeahead
                            control={control}
                            id="name"
                            onChange={(e) => {
                                const f = families.find((f) => f.name === e[0]);
                                if (f) {
                                    setValue('description', f.description);
                                }
                            }}
                            placeholder="Name"
                            options={families.map((f) => f.name)}
                            clearButton
                            isInvalid={!!errors.name}
                            newSelectionPrefix="Add a new Family: "
                            allowNew={true}
                        />
                        {errors.name && <span className="text-danger">The Name is required. {JSON.stringify(errors)}</span>}
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

export const getServerSideProps: GetServerSideProps = async () => {
    return {
        props: {
            families: await allFamilies(),
        },
    };
};
export default Family;
