import { abundance, family, species } from '@prisma/client';
import { GetServerSideProps } from 'next';
import React, { useState } from 'react';
import { Col, Row } from 'react-bootstrap';
import { useForm } from 'react-hook-form';
import { allFamilies } from '../../libs/db/family';
import { abundances } from '../../libs/db/species';
import { genOptions } from '../../libs/utils/forms';
import * as yup from 'yup';
import { yupResolver } from '@hookform/resolvers/yup';
import { useRouter } from 'next/router';
import { DeleteResults, SpeciesUpsertFields } from '../../libs/apitypes';
import Auth from '../../components/auth';
import ControlledTypeahead from '../../components/controlledtypeahead';
import { allHosts } from '../../libs/db/host';

type Props = {
    hosts: species[];
    families: family[];
    abundances: abundance[];
};

const extractGenus = (n: string): string => {
    return n.split(' ')[0];
};

const Schema = yup.object().shape({
    name: yup.string().matches(/([A-Z][a-z]+ [a-z]+$)/),
    family: yup.string().required(),
});

const Host = ({ hosts, families, abundances }: Props): JSX.Element => {
    const [existing, setExisting] = useState(false);
    const [deleteResults, setDeleteResults] = useState<DeleteResults>();

    const { register, handleSubmit, setValue, errors, control, reset } = useForm({
        mode: 'onBlur',
        resolver: yupResolver(Schema),
    });

    const router = useRouter();

    const setFamily = (id: number): void => {
        const family = families.find((f) => f.id === id);
        if (family) setValue('family', family.name);
    };
    const setAbundance = (id: number | null): void => {
        const abundance = families.find((f) => f.id === id);
        if (abundance) setValue('family', abundance.name);
    };

    const onSubmit = async (data: SpeciesUpsertFields) => {
        try {
            if (data.delete) {
                const id = hosts.find((h) => h.name === data.name)?.id;
                const res = await fetch(`../api/host/${id}`, {
                    method: 'DELETE',
                });

                if (res.status === 200) {
                    setDeleteResults(await res.json());
                } else {
                    throw new Error(await res.text());
                }
            } else {
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
            }
            reset();
        } catch (e) {
            console.error(e);
        }
    };

    return (
        <Auth>
            <form onSubmit={handleSubmit(onSubmit)} className="m-4 pr-4">
                <h4>Add A Host</h4>
                <Row className="form-group">
                    <Col>
                        Name (binomial):
                        <ControlledTypeahead
                            control={control}
                            name="name"
                            onChange={(e) => {
                                setExisting(false);
                                const f = hosts.find((f) => f.name === e[0]);
                                if (f) {
                                    setExisting(true);
                                    setFamily(f.family_id);
                                    setAbundance(f.abundance_id);
                                    setValue('commonnames', f.commonnames);
                                    setValue('synonyms', f.synonyms);
                                }
                            }}
                            onBlur={(e) => {
                                if (!errors.name) {
                                    setValue('genus', extractGenus(e.target.value));
                                }
                            }}
                            placeholder="Name"
                            options={hosts.map((f) => f.name)}
                            clearButton
                            isInvalid={!!errors.name}
                            newSelectionPrefix="Add a new Host: "
                            allowNew={true}
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
                <Row className="fromGroup" hidden={!existing}>
                    <Col xs="1">Delete?:</Col>
                    <Col className="mr-auto">
                        <input name="delete" type="checkbox" className="form-check-input" ref={register} />
                    </Col>
                </Row>
                <Row className="formGroup">
                    <Col>
                        <input type="submit" className="button" />
                    </Col>
                </Row>
                <Row hidden={!deleteResults}>
                    <Col>{`Deleted ${deleteResults?.name}.`}</Col>
                </Row>
            </form>
        </Auth>
    );
};

export const getServerSideProps: GetServerSideProps = async () => {
    return {
        props: {
            hosts: await allHosts(),
            families: await allFamilies(),
            abundances: await abundances(),
        },
    };
};

export default Host;
