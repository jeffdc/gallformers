import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetServerSideProps } from 'next';
import Link from 'next/link';
import { useRouter } from 'next/router';
import { ParsedUrlQuery } from 'querystring';
import React from 'react';
import { Col, Row } from 'react-bootstrap';
import * as yup from 'yup';
import Auth from '../../components/auth';
import ControlledTypeahead from '../../components/controlledtypeahead';
import useAdmin from '../../hooks/useadmin';
import { AdminFormFields } from '../../hooks/useAPIs';
import { extractQueryParam } from '../../libs/api/apipage';
import { GallApi, GallHost, GallHostUpdateFields, HostTaxon, SimpleSpecies } from '../../libs/api/apitypes';
import { TaxonomyEntry } from '../../libs/api/taxonomy';
import { allGalls } from '../../libs/db/gall';
import { allHosts } from '../../libs/db/host';
import { allGenera } from '../../libs/db/taxonomy';
import Admin from '../../libs/pages/admin';
import { hasProp, mightFailWithArray } from '../../libs/utils/util';

type Props = {
    id: string;
    galls: GallApi[];
    genera: string[];
    hosts: SimpleSpecies[];
};

const schema = yup.object().shape({
    value: yup.array().required('You must provide the gall.'),
});

type FormFields = AdminFormFields<GallApi> & {
    genus: string;
    hosts: GallHost[];
};

const update = (s: GallApi, newValue: string) => ({
    ...s,
    name: newValue,
});

// eslint-disable-next-line @typescript-eslint/no-unused-vars
const toUpsertFields = (fields: FormFields, name: string, id: number): GallHostUpdateFields => {
    return {
        gall: id,
        hosts: fields.hosts.map((h) => h.id),
        genus: fields.genus[0],
    };
};

const fetchGallHosts = async (id: number | undefined): Promise<GallHost[]> => {
    if (id == undefined) return [];

    const res = await fetch(`../api/gallhost?gallid=${id}`);
    if (res.status === 200) {
        return (await res.json()) as GallHost[];
    } else {
        console.error(await res.text());
        throw new Error('Failed to fetch host for the selected gall. Check console.');
    }
};

const GallHostMapper = ({ id, galls, genera, hosts }: Props): JSX.Element => {
    const updatedFormFields = async (gall: GallApi | undefined): Promise<FormFields> => {
        if (gall != undefined) {
            const hosts = await fetchGallHosts(gall.id);
            return {
                mainField: [gall],
                hosts: hosts,
                genus: '',
                del: false,
            };
        }

        setSelected(gall);
        router.replace(``, undefined, { shallow: true });

        return {
            mainField: [],
            hosts: [],
            genus: '',
            del: false,
        };
    };

    // eslint-disable-next-line prettier/prettier
    const {
        data,
        selected,
        setSelected,
        error,
        setError,
        deleteResults,
        setDeleteResults,
        form,
        formSubmit,
    } = useAdmin<GallApi, FormFields, GallHostUpdateFields>(
        'Gall-Host',
        id,
        galls,
        update,
        toUpsertFields,
        { keyProp: 'name', delEndpoint: '../api/gallhost/', upsertEndpoint: '../api/gallhost/insert' },
        schema,
        updatedFormFields,
    );

    const router = useRouter();

    return (
        <Auth>
            <Admin
                type="Gall & Host Mappings"
                keyField="name"
                setError={setError}
                error={error}
                setDeleteResults={setDeleteResults}
                deleteResults={deleteResults}
                selected={selected}
            >
                <form onSubmit={form.handleSubmit(formSubmit)} className="m-4 pr-4">
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
                                control={form.control}
                                name="value"
                                placeholder="Gall"
                                options={data}
                                labelKey="name"
                                clearButton
                                isInvalid={!!form.errors.value}
                                onChange={(s) => {
                                    if (s.length > 0) {
                                        setSelected(s[0]);
                                        router.replace(`?id=${s[0].id}`, undefined, { shallow: true });
                                    } else {
                                        setSelected(undefined);
                                        router.replace(``, undefined, { shallow: true });
                                    }
                                }}
                            />
                            {form.errors.value && hasProp(form.errors.value, 'message') && (
                                <span className="text-danger">{form.errors.value.message as string}</span>
                            )}
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
                                control={form.control}
                                name="hosts"
                                placeholder="Hosts"
                                options={hosts}
                                labelKey="name"
                                multiple
                                clearButton
                                disabled={!selected}
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
                                control={form.control}
                                name="genus"
                                placeholder="Genus"
                                options={genera}
                                disabled={!selected}
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
                </form>
            </Admin>
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
    const genera = (await mightFailWithArray<TaxonomyEntry>()(allGenera(HostTaxon))).map((g) => g.name);

    return {
        props: {
            id: id,
            galls: await mightFailWithArray<GallApi>()(allGalls()),
            genera: genera,
            hosts: await mightFailWithArray<SimpleSpecies>()(allHosts()),
        },
    };
};

export default GallHostMapper;
