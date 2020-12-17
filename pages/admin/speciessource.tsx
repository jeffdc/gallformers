import { yupResolver } from '@hookform/resolvers/yup';
import { source, species, speciessource } from '@prisma/client';
import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetServerSideProps } from 'next';
import Link from 'next/link';
import React, { useState } from 'react';
import { Col, Row } from 'react-bootstrap';
import { useForm } from 'react-hook-form';
import * as yup from 'yup';
import Auth from '../../components/auth';
import ControlledTypeahead from '../../components/controlledtypeahead';
import { DeleteResult, GallTaxon, SpeciesSourceApi, SpeciesSourceInsertFields } from '../../libs/api/apitypes';
import { allSources } from '../../libs/db/source';
import { allSpecies } from '../../libs/db/species';
import { mightFailWithArray } from '../../libs/utils/util';

type Props = {
    species: species[];
    sources: source[];
};

const Schema = yup.object().shape({
    species: yup.array().required(),
    source: yup.array().required(),
});

type FormFields = {
    species: string;
    source: string;
    description: string | null;
    useasdefault: boolean;
    delete: boolean;
};

const SpeciesSource = ({ species, sources }: Props): JSX.Element => {
    const [results, setResults] = useState<speciessource>();
    const [isGall, setIsGall] = useState(true);
    const [existing, setExisting] = useState(false);
    const [deleteResults, setDeleteResults] = useState<DeleteResult>();

    const { handleSubmit, errors, control, register, reset, setValue, getValues } = useForm<FormFields>({
        mode: 'onBlur',
        resolver: yupResolver(Schema),
    });

    const lookup = (speciesName: string, sourceTitle: string) => {
        return {
            sp: species.find((sp) => sp.name.localeCompare(speciesName) === 0),
            so: sources.find((so) => so.title.localeCompare(sourceTitle) === 0),
        };
    };

    const checkAlreadyExists = async () => {
        try {
            const species = getValues('species');
            const source = getValues('source');
            setValue('description', '');
            setValue('useasdefault', false);

            const { sp, so } = lookup(species, source);
            if (sp != undefined && so != undefined) {
                const res = await fetch(`../api/speciessource?speciesid=${sp?.id}&sourceid=${so?.id}`);

                setExisting(false);
                if (res.status === 200) {
                    const s = (await res.json()) as SpeciesSourceApi[];
                    if (s && s.length > 0) {
                        setExisting(true);
                        setValue('description', pipe(s[0].description, O.getOrElse(constant(''))));
                        setValue('useasdefault', s[0].useasdefault > 0);
                    }
                }
            }
        } catch (e) {
            console.error(e);
        }
    };

    const onSubmit = async (data: FormFields) => {
        try {
            const { sp, so } = lookup(data.species[0], data.source[0]);
            if (!sp || !so) throw new Error('Somehow either the source or the species selected is invalid.');

            if (data.delete) {
                const res = await fetch(`../api/speciessource?speciesid=${sp?.id}&sourceid=${so?.id}`, {
                    method: 'DELETE',
                });

                if (res.status === 200) {
                    reset();
                    setDeleteResults(await res.json());
                    return;
                } else {
                    throw new Error(await res.text());
                }
            }

            setIsGall(sp.taxoncode === GallTaxon);

            const insertData: SpeciesSourceInsertFields = {
                species: sp.id,
                source: so.id,
                description: data.description ? data.description : '',
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
                reset();
                setResults(await res.json());
            } else {
                throw new Error(await res.text());
            }
        } catch (e) {
            console.error(e);
        }
    };

    return (
        <Auth>
            <form onSubmit={handleSubmit(onSubmit)} className="m-4 pr-4">
                <h4>Map Species & Sources</h4>
                <p>
                    First select both a species and a source. If a mapping already exists then the description will display.Then
                    you can edit the mapping.
                </p>
                <Row className="form-group">
                    <Col>
                        Species:
                        <ControlledTypeahead
                            control={control}
                            name="species"
                            placeholder="Species"
                            options={species.map((h) => h.name)}
                            isInvalid={!!errors.species}
                            onBlur={checkAlreadyExists}
                            clearButton
                        />
                        {errors.species && <span className="text-danger">You must provide a species to map.</span>}
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
                            name="source"
                            placeholder="Sources"
                            options={sources.map((h) => h.title)}
                            isInvalid={!!errors.source}
                            onBlur={checkAlreadyExists}
                            clearButton
                        />
                        {errors.source && <span className="text-danger">You must provide a source to map.</span>}
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
                <Row className="fromGroup" hidden={!existing}>
                    <Col xs="1">Delete?:</Col>
                    <Col className="mr-auto">
                        <input name="delete" type="checkbox" className="form-check-input" ref={register} />
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
                {results && (
                    <>
                        <span>
                            Mapped{' '}
                            <Link href={`/source/${results.source_id}`}>
                                <a>source</a>
                            </Link>{' '}
                            to{' '}
                            <Link href={`/${isGall ? 'gall' : 'host'}/${results.species_id}`}>
                                <a>species</a>
                            </Link>
                            .
                        </span>
                    </>
                )}
            </form>
        </Auth>
    );
};

export const getServerSideProps: GetServerSideProps = async () => {
    return {
        props: {
            species: await mightFailWithArray<species>()(allSpecies()),
            sources: await mightFailWithArray<source>()(allSources()),
        },
    };
};

export default SpeciesSource;
