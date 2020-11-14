import { yupResolver } from '@hookform/resolvers/yup';
import { species, source, speciessource } from '@prisma/client';
import { GetServerSideProps } from 'next';
import Link from 'next/link';
import { useRouter } from 'next/router';
import React, { useState } from 'react';
import { Col, ListGroup, ListGroupItem, Row } from 'react-bootstrap';
import { Typeahead } from 'react-bootstrap-typeahead';
import { Controller, useForm } from 'react-hook-form';
import * as yup from 'yup';
import Auth from '../../components/auth';
import { SpeciesSourceInsertFields } from '../../libs/apitypes';
import { allSources } from '../../libs/db/source';
import { allSpecies } from '../../libs/db/species';
import { normalizeToArray } from '../../libs/utils/forms';

type Props = {
    species: species[];
    sources: source[];
};

const Schema = yup.object().shape({
    species: yup.array().required(),
    sources: yup.array().required(),
});

const SpeciesSource = ({ species, sources }: Props): JSX.Element => {
    const [results, setResults] = useState(new Array<speciessource>());
    const { handleSubmit, errors, control } = useForm({
        mode: 'onBlur',
        resolver: yupResolver(Schema),
    });

    const onSubmit = async (data: { species: string[]; sources: string[] }) => {
        try {
            const insertData: SpeciesSourceInsertFields = {
                species: data.species.map((s) => {
                    // i hate null... :( these should be safe since the text values came from the same place as the ids
                    // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
                    return species.find((sp) => s === sp.name)!.id;
                }),
                sources: data.sources.map((s) => {
                    // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
                    return sources.find((so) => s === so.title)!.id;
                }),
            };

            const res = await fetch('../api/speciessource/insert', {
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
                        <Controller
                            control={control}
                            name="species"
                            defaultValue={[]}
                            render={({ value, onChange, onBlur }) => (
                                <Typeahead
                                    onChange={(e: string | string[]) => {
                                        onChange(e);
                                    }}
                                    onBlur={onBlur}
                                    selected={normalizeToArray(value)}
                                    placeholder="Species"
                                    id="Species"
                                    options={species.map((h) => h.name)}
                                    multiple
                                    clearButton
                                    isInvalid={!!errors.species}
                                />
                            )}
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
                        <Controller
                            control={control}
                            name="sources"
                            defaultValue={[]}
                            render={({ value, onChange, onBlur }) => (
                                <Typeahead
                                    onChange={(e: string | string[]) => {
                                        onChange(e);
                                    }}
                                    onBlur={onBlur}
                                    selected={normalizeToArray(value)}
                                    placeholder="Sources"
                                    id="Sources"
                                    options={sources.map((h) => h.title)}
                                    multiple
                                    clearButton
                                    isInvalid={!!errors.species}
                                />
                            )}
                        />
                        {errors.sources && <span className="text-danger">You must provide a least one source to map.</span>}
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        <input type="submit" className="button" />
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
                                        <Link href={`/gall/${r.species_id}`}>
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
