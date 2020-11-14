import { abundance, family } from '@prisma/client';
import { GetServerSideProps } from 'next';
import React from 'react';
import { Col, Row } from 'react-bootstrap';
import { useForm } from 'react-hook-form';
import { allFamilies } from '../../libs/db/family';
import { abundances } from '../../libs/db/species';
import { genOptions } from '../../libs/utils/forms';
import * as yup from 'yup';
import { yupResolver } from '@hookform/resolvers/yup';
import { useRouter } from 'next/router';
import { SpeciesUpsertFields } from '../../libs/apitypes';
import Auth from '../../components/auth';

type Props = {
    families: family[];
    abundances: abundance[];
};

const extractGenus = (n: string): string => {
    return n.split(' ')[0];
};

const Schema = yup.object().shape({
    name: yup.string().matches(/([A-Z][a-z]+ [a-z]+$)/),
    family: yup.string().required(),
    description: yup.string().required(),
});

const Host = ({ families, abundances }: Props): JSX.Element => {
    const { register, handleSubmit, setValue, errors } = useForm({
        mode: 'onBlur',
        resolver: yupResolver(Schema),
    });

    const router = useRouter();

    const onSubmit = async (data: SpeciesUpsertFields) => {
        try {
            const res = await fetch('../api/host/upsert', {
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
                <h4>Add A Host</h4>
                <Row className="form-group">
                    <Col>
                        Name (binomial):
                        <input
                            type="text"
                            placeholder="Name"
                            name="name"
                            className="form-control"
                            onBlur={(e) => (!errors.name ? setValue('genus', extractGenus(e.target.value)) : undefined)}
                            ref={register}
                        />
                        {errors.name && (
                            <span className="text-danger">
                                Name is required and must be in standard binomial form, e.g., Andricus weldi
                            </span>
                        )}
                    </Col>
                    <Col>
                        Genus (filled automatically):
                        <input type="text" name="genus" className="form-control" readOnly tabIndex={-1} ref={register} />
                    </Col>
                    <Col>
                        Family:
                        <select name="family" className="form-control" ref={register}>
                            {genOptions(families.map((f) => (f.name ? f.name : '')))}
                        </select>
                        {errors.family && (
                            <span className="text-danger">
                                The Family name is required. If it is not present in the list you will have to go add the family
                                first. :(
                            </span>
                        )}
                    </Col>
                    <Col>
                        Abundance:
                        <select name="abundance" className="form-control" ref={register}>
                            {genOptions(abundances.map((a) => (a.abundance ? a.abundance : '')))}
                        </select>
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        Common Names (comma-delimited):
                        <input
                            type="text"
                            placeholder="Common Names"
                            name="commonnames"
                            className="form-control"
                            ref={register}
                        />
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        Synonyms (comma-delimited):
                        <input type="text" placeholder="Synonyms" name="synonyms" className="form-control" ref={register} />
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        <p>Description:</p>
                        <textarea name="description" className="form-control" ref={register} />
                        {errors.description && (
                            <span className="text-danger">
                                You must provide a description. You can add source references separately.
                            </span>
                        )}
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
            abundances: await abundances(),
        },
    };
};

export default Host;
