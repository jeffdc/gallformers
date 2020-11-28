import { yupResolver } from '@hookform/resolvers/yup';
import { source, species, speciessource } from '@prisma/client';
import { GetServerSideProps } from 'next';
import Link from 'next/link';
import React, { useState } from 'react';
import { Col, ListGroup, ListGroupItem, Row } from 'react-bootstrap';
import { useForm } from 'react-hook-form';
import * as yup from 'yup';
import Auth from '../../components/auth';
import ControlledTypeahead from '../../components/controlledtypeahead';
import { SpeciesSourceInsertFields } from '../../libs/apitypes';
import { GallTaxon } from '../../libs/db/dbinternaltypes';
import { allSources } from '../../libs/db/source';
import { allSpecies } from '../../libs/db/species';

type Props = {
    species: species[];
    sources: source[];
};

const Schema = yup.object().shape({
    species: yup.array().required(),
    sources: yup.array().required(),
});

type FormFields = {
    species: string;
    source: string;
    description: string;
    useasdefault: boolean;
};

const SpeciesSource = ({ species, sources }: Props): JSX.Element => {
    const [results, setResults] = useState(new Array<speciessource>());
    const [isGall, setIsGall] = useState(true);

    const { handleSubmit, errors, control, register } = useForm({
        mode: 'onBlur',
        resolver: yupResolver(Schema),
    });

    const onSubmit = async (data: FormFields) => {
        try {
            const sp = species.find((sp) => data.species === sp.name);
            const so = sources.find((so) => data.source === so.title);
            if (!sp || !so) throw new Error('Somehow either the source or the species selected is invalid.');

            setIsGall(sp.taxoncode === GallTaxon);

            const insertData: SpeciesSourceInsertFields = {
                species: sp.id,
                source: so.id,
                description: data.description,
                useasdefault: data.useasdefault,
            };

            const res = await fetch('../api/speciessource/upsert', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(insertData),
            });

            if (res.status === 200) {
                setResults(await res.json());
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
                <h4>Map Species & Sources</h4>
                <Row className="form-group">
                    <Col>
                        Species:
                        <ControlledTypeahead
                            control={control}
                            name="species"
                            placeholder="Species"
                            options={species.map((h) => h.name)}
                            isInvalid={!!errors.species}
                        />
                        {errors.species && <span className="text-danger">You must provide a least one species to map.</span>}
                    </Col>
                </Row>
                <Row>
                    <Col xs={1} className="p-0 m-0 mx-auto">
                        <h2>⇅</h2>
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        Source:
                        <ControlledTypeahead
                            control={control}
                            name="sources"
                            placeholder="Sources"
                            options={sources.map((h) => h.title)}
                            isInvalid={!!errors.sources}
                        />
                        {errors.sources && <span className="text-danger">You must provide a least one source to map.</span>}
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        Description (this is the relevant info from the selected Source about the selected Species):
                        <textarea name="description" className="form-control" ref={register} rows={8} />
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        <input type="checkbox" name="useasdefault" className="form-check-inline" ref={register} />
                        <label className="form-check-label">Use as Default?</label>
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        <input type="submit" className="btn-primary" />
                    </Col>
                </Row>
                {results.length > 0 && (
                    <>
                        <span>Wrote {results.length} species-source mappings.</span>
                        <ListGroup>
                            {results.map((r) => {
                                return (
                                    <ListGroupItem key={r.id}>
                                        Added{' '}
                                        <Link href={`/source/${r.source_id}`}>
                                            <a>source</a>
                                        </Link>{' '}
                                        to{' '}
                                        <Link href={`/${isGall ? 'gall' : 'host'}/${r.species_id}`}>
                                            <a>species</a>
                                        </Link>
                                        .
                                    </ListGroupItem>
                                );
                            })}
                        </ListGroup>
                    </>
                )}
            </form>
        </Auth>
    );
};

export const getServerSideProps: GetServerSideProps = async () => {
    return {
        props: {
            species: await allSpecies(),
            sources: await allSources(),
        },
    };
};

export default SpeciesSource;
