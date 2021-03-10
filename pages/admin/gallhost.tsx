import { yupResolver } from '@hookform/resolvers/yup';
import { host } from '@prisma/client';
import * as O from 'fp-ts/lib/Option';
import { constant, pipe } from 'fp-ts/lib/function';
import { GetServerSideProps } from 'next';
import Head from 'next/head';
import Link from 'next/link';
import { ParsedUrlQuery } from 'querystring';
import React, { useCallback, useEffect, useState } from 'react';
import { Alert, Col, Row } from 'react-bootstrap';
import { useForm } from 'react-hook-form';
import * as yup from 'yup';
import Auth from '../../components/auth';
import ControlledTypeahead from '../../components/controlledtypeahead';
import { extractQueryParam } from '../../libs/api/apipage';
import { GallApi, GallHostUpdateFields, SimpleSpecies } from '../../libs/api/apitypes';
import { allGalls } from '../../libs/db/gall';
import { allHostGenera, allHosts } from '../../libs/db/host';
import { mightFailWithArray } from '../../libs/utils/util';
import { useRouter } from 'next/router';

type Props = {
    id: string;
    galls: GallApi[];
    genera: string[];
    hosts: SimpleSpecies[];
};

const Schema = yup.object().shape({
    gall: yup.mixed().required(),
});

type FormFields = {
    gall: GallApi[];
    genus: string;
    hosts: SimpleSpecies[];
};

const GallHost = ({ id, galls, genera, hosts }: Props): JSX.Element => {
    const [results, setResults] = useState(new Array<host>());
    const [selectedGall, setSelectedGall] = useState(id ? galls.find((g) => g.id === parseInt(id)) : undefined);
    const [error, setError] = useState('');

    const { handleSubmit, errors, control, setValue, reset } = useForm<FormFields>({
        mode: 'onBlur',
        resolver: yupResolver(Schema),
    });

    const router = useRouter();

    const onSubmit = async (data: FormFields) => {
        try {
            const insertData: GallHostUpdateFields = {
                gall: data.gall[0].id,
                hosts: data.hosts.map((h) => h.id),
                genus: data.genus[0],
            };

            const res = await fetch('../api/gallhost/insert', {
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
                const text = await res.text();
                console.error(`Got an error back code: ${res.status} and text: ${text}.`);
                throw new Error(text);
            }
        } catch (e) {
            console.error(e);
            setError(e);
        }
    };

    const gallChange = async (gs: GallApi[]) => {
        const gall = gs.length > 0 ? gs[0] : undefined;
        if (gall != undefined) {
            const res = await fetch(`../api/gallhost?gallid=${gall.id}`);
            if (res.status === 200) {
                const hosts = (await res.json()) as SimpleSpecies[];
                if (hosts) {
                    setSelectedGall(gall);
                }
            }
            router.replace(`?id=${gall.id}`, undefined, { shallow: true });
        } else {
            setSelectedGall(gall);
            router.replace(``, undefined, { shallow: true });
        }
    };

    const onGallChange = useCallback(
        (gall: GallApi | undefined) => {
            if (gall == undefined) {
                reset({
                    gall: [],
                    hosts: [],
                    genus: '',
                });
            } else {
                reset({
                    gall: [gall],
                    hosts: gall.hosts,
                    genus: '',
                });
            }
        },
        [reset],
    );

    useEffect(() => {
        onGallChange(selectedGall);
    }, [selectedGall, onGallChange]);

    return (
        <Auth>
            <>
                <Head>
                    <title>Map Galls & Hosts</title>
                </Head>

                {error.length > 0 && (
                    <Alert variant="danger" onClose={() => setError('')} dismissible>
                        <Alert.Heading>Uh-oh</Alert.Heading>
                        <p>{error}</p>
                    </Alert>
                )}

                <form onSubmit={handleSubmit(onSubmit)} className="m-4 pr-4">
                    <h4>Map Galls & Hosts</h4>
                    <p>
                        First select a gall. If any mappings to hosts already exist they will show up in the Host field. Then you
                        can edit these mappings (add or delete).
                    </p>
                    <p>
                        At least one host species (not just a Genus) must exist before mapping.{' '}
                        <Link href="./host">
                            <a>Go add one</a>
                        </Link>{' '}
                        now if you need to.
                    </p>
                    <Row className="form-group">
                        <Col>
                            Gall:
                            <ControlledTypeahead
                                control={control}
                                name="gall"
                                placeholder="Gall"
                                options={galls}
                                labelKey="name"
                                clearButton
                                isInvalid={!!errors.gall}
                                onChange={gallChange}
                            />
                            {errors.gall && <span className="text-danger">You must provide a gall to map.</span>}
                        </Col>
                    </Row>
                    <Row>
                        <Col xs={1} className="p-0 m-0 mx-auto">
                            <h2>⇅</h2>
                        </Col>
                    </Row>
                    <Row className="form-group">
                        <Col>
                            Hosts:
                            <ControlledTypeahead
                                control={control}
                                name="hosts"
                                placeholder="Hosts"
                                options={hosts}
                                labelKey="name"
                                multiple
                                clearButton
                                disabled={!selectedGall}
                            />
                        </Col>
                    </Row>
                    <Row>
                        <Col xs={1} className="p-0 m-0 mx-auto">
                            <h4> -or- </h4>
                        </Col>
                    </Row>
                    <Row className="form-group">
                        <Col>
                            Genus:
                            <ControlledTypeahead
                                control={control}
                                name="genus"
                                placeholder="Genus"
                                options={genera}
                                disabled={!selectedGall}
                                clearButton
                            />
                            (If you select a Genus, then the mapping will be created for ALL species in that Genus. Once the
                            individual mappings are created you can edit them individually. This will NOT overwrite any existing
                            mappings for the gall.)
                        </Col>
                    </Row>
                    <Row className="form-group">
                        <Col>
                            <input type="submit" className="button" value="Submit" />
                        </Col>
                    </Row>
                    {results.length > 0 && <span>Updated gall-host mappings.</span>}
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
            id: id,
            galls: await mightFailWithArray<GallApi>()(allGalls()),
            genera: await mightFailWithArray<string>()(allHostGenera()),
            hosts: await mightFailWithArray<SimpleSpecies>()(allHosts()),
        },
    };
};

export default GallHost;
