import { yupResolver } from '@hookform/resolvers/yup';
import { source, species, speciessource } from '@prisma/client';
import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetServerSideProps } from 'next';
import Head from 'next/head';
import Link from 'next/link';
import { useRouter } from 'next/router';
import { ParsedUrlQuery } from 'querystring';
import React, { useCallback, useEffect, useState } from 'react';
import { Alert, Col, Row } from 'react-bootstrap';
import { useForm } from 'react-hook-form';
import * as yup from 'yup';
import Auth from '../../components/auth';
import ControlledTypeahead from '../../components/controlledtypeahead';
import { extractQueryParam } from '../../libs/api/apipage';
import { DeleteResult, GallTaxon, SpeciesSourceApi, SpeciesSourceInsertFields } from '../../libs/api/apitypes';
import { allSources } from '../../libs/db/source';
import { allSpecies } from '../../libs/db/species';
import { mightFailWithArray } from '../../libs/utils/util';

type Props = {
    speciesid: string;
    species: species[];
    sources: source[];
};

const Schema = yup.object().shape({
    species: yup.string().required(),
    source: yup.string().required(),
});

type FormFields = {
    species: string;
    source: string;
    description: string | null;
    useasdefault: boolean;
    delete: boolean;
    externallink: string;
};

const SpeciesSource = ({ speciesid, species, sources }: Props): JSX.Element => {
    const [existingSpeciesId, setExistingSpeciesId] = useState<number | undefined>(
        speciesid && speciesid !== '' ? parseInt(speciesid) : undefined,
    );
    const [results, setResults] = useState<speciessource>();
    const [isGall, setIsGall] = useState(true);
    const [existing, setExisting] = useState(false);
    const [deleteResults, setDeleteResults] = useState<DeleteResult>();
    const [error, setError] = useState('');

    const router = useRouter();

    const { handleSubmit, errors, control, register, reset, getValues } = useForm<FormFields>({
        mode: 'onBlur',
        resolver: yupResolver(Schema),
    });

    const onSpeciesChange = useCallback(
        (spid: number | undefined) => {
            console.log('ID: ' + spid);
            if (spid == undefined) {
                reset({
                    species: '',
                    source: '',
                    description: '',
                    useasdefault: false,
                    externallink: '',
                    delete: false,
                });
            } else {
                try {
                    const sp = species.find((s) => s.id === spid);
                    if (sp == undefined) {
                        throw new Error(`Somehow we have a species selection that does not exist?! speciesid: ${spid}`);
                    }
                    reset({
                        species: sp.name,
                        source: '',
                        description: '',
                        useasdefault: false,
                        externallink: '',
                        delete: false,
                    });
                } catch (e) {
                    console.error(e);
                    setError(e);
                }
            }
        },
        [reset, species],
    );

    useEffect(() => {
        onSpeciesChange(existingSpeciesId);
    }, [existingSpeciesId, onSpeciesChange]);

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
            console.log(`Checking with: '${species}' and '${source}'`);

            const { sp, so } = lookup(species, source);
            if (sp != undefined) {
                setExistingSpeciesId(sp.id);
                router.replace(`?id=${sp.id}`, undefined, { shallow: true });
            } else {
                setExistingSpeciesId(undefined);
                router.replace(``, undefined, { shallow: true });
            }

            if (sp != undefined && so != undefined) {
                const res = await fetch(`../api/speciessource?speciesid=${sp?.id}&sourceid=${so?.id}`);

                if (res.status === 200) {
                    const s = (await res.json()) as SpeciesSourceApi[];
                    if (s && s.length > 0) {
                        setExisting(true);
                        reset({
                            species: sp.name,
                            source: so.title,
                            description: s[0].description,
                            useasdefault: s[0].useasdefault > 0,
                            externallink: s[0].externallink,
                        });
                    }
                } else {
                    setExisting(false);
                }
            }
        } catch (e) {
            console.error(e);
            setError(e);
        }
    };

    const onSubmit = async (data: FormFields) => {
        try {
            const { sp, so } = lookup(data.species, data.source);
            if (!sp || !so) throw new Error('Somehow either the source or the species selected is invalid.');

            if (data.delete) {
                const res = await fetch(`../api/speciessource?speciesid=${sp?.id}&sourceid=${so?.id}`, {
                    method: 'DELETE',
                });

                if (res.status === 200) {
                    setExisting(false);
                    setExistingSpeciesId(undefined);
                    router.replace(``, undefined, { shallow: true });
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
                externallink: data.externallink,
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
                setExisting(true);
            } else {
                throw new Error(await res.text());
            }
        } catch (e) {
            console.error(e);
            setError(e);
        }
    };

    return (
        <Auth>
            <>
                <Head>
                    <title>Map Species & Sources</title>
                </Head>

                {error.length > 0 && (
                    <Alert variant="danger" onClose={() => setError('')} dismissible>
                        <Alert.Heading>Uh-oh</Alert.Heading>
                        <p>{error}</p>
                    </Alert>
                )}

                <form onSubmit={handleSubmit(onSubmit)} className="m-4 pr-4">
                    <h4>Map Species & Sources</h4>
                    <p>
                        First select both a species and a source. If a mapping already exists then the description will display.
                        Then you can edit the mapping.
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
                            {errors.species && <span className="text-danger">You must provide a species or genus to map.</span>}
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
                                placeholder="Source"
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
                            Direct Link to Description Page (if available, eg at BHL or HathiTrust. Do not duplicate main
                            source-level link or link to a pdf):
                            <input type="text" placeholder="" name="externallink" className="form-control" ref={register} />
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
            speciesid: id,
            species: await mightFailWithArray<species>()(allSpecies()),
            sources: await mightFailWithArray<source>()(allSources()),
        },
    };
};

export default SpeciesSource;
