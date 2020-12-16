import { yupResolver } from '@hookform/resolvers/yup';
import { host } from '@prisma/client';
import { GetServerSideProps } from 'next';
import React, { useState } from 'react';
import { Col, Row } from 'react-bootstrap';
import { useForm } from 'react-hook-form';
import * as yup from 'yup';
import Auth from '../../components/auth';
import ControlledTypeahead from '../../components/controlledtypeahead';
import { GallApi, GallHostUpdateFields, SimpleSpecies } from '../../libs/api/apitypes';
import { allGalls } from '../../libs/db/gall';
import { allHosts } from '../../libs/db/host';
import { mightFailWithArray } from '../../libs/utils/util';

type Props = {
    galls: GallApi[];
    hosts: SimpleSpecies[];
};

const Schema = yup.object().shape({
    galls: yup.array().required(),
    hosts: yup.array().required(),
});

type FormFields = {
    gall: GallApi;
    hosts: SimpleSpecies[];
};

const GallHost = ({ galls, hosts }: Props): JSX.Element => {
    const [results, setResults] = useState(new Array<host>());
    const [selectedGall, setSelectedGall] = useState<GallApi>();

    const { handleSubmit, errors, control, setValue } = useForm<FormFields>({
        mode: 'onBlur',
        resolver: yupResolver(Schema),
    });

    const onSubmit = async (data: FormFields) => {
        try {
            const insertData: GallHostUpdateFields = {
                gall: data.gall.id,
                hosts: data.hosts.map((h) => h.id),
            };

            const res = await fetch('../api/gallhost/insert', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(insertData),
            });

            if (res.status === 200) {
                setResults(await res.json());
            } else {
                const text = await res.text();
                console.error(`Got an error back code: ${res.status} and text: ${text}.`);
                throw new Error(text);
            }
        } catch (e) {
            console.error(e);
        }
    };

    const gallChange = async (gs: GallApi[]) => {
        const gall = gs.length > 0 ? gs[0] : undefined;
        if (gall != undefined) {
            const res = await fetch(`../api/gallhost?gall=${gall}`);
            if (res.status === 200) {
                const hosts = (await res.json()) as SimpleSpecies[];
                if (hosts) {
                    setSelectedGall(gall);
                    setValue('hosts', hosts);
                }
            }
        } else {
            setSelectedGall(gall);
            setValue('hosts', []);
        }
    };

    return (
        <Auth>
            <form onSubmit={handleSubmit(onSubmit)} className="m-4 pr-4">
                <h4>Map Galls & Hosts</h4>
                <p>
                    First select a gall. If any mappings to hosts already exist they will show up in the Host field. Then you can
                    edit these mappings (add or delete).
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
                        {errors.gall && <span className="text-danger">You must provide a least one gall to map.</span>}
                    </Col>
                </Row>
                <Row>
                    <Col xs={1} className="p-0 m-0 mx-auto">
                        <h2>⇅</h2>
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        Host:
                        <ControlledTypeahead
                            control={control}
                            name="hosts"
                            placeholder="Hosts"
                            options={hosts}
                            labelKey="name"
                            multiple
                            clearButton
                            isInvalid={!!errors.hosts}
                            disabled={!selectedGall}
                        />
                        {errors.hosts && <span className="text-danger">You must provide a least one host to map.</span>}
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        <input type="submit" className="button" />
                    </Col>
                </Row>
                {results.length > 0 && <span>Updated gall-host mappings.</span>}
            </form>
        </Auth>
    );
};

export const getServerSideProps: GetServerSideProps = async () => {
    return {
        props: {
            galls: await mightFailWithArray<GallApi>()(allGalls()),
            hosts: await mightFailWithArray<SimpleSpecies>()(allHosts()),
        },
    };
};

export default GallHost;
