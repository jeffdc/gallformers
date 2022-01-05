import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetServerSideProps } from 'next';
import Link from 'next/link';
import { ParsedUrlQuery } from 'querystring';
import React, { useEffect, useState } from 'react';
import { Button, Col, Row } from 'react-bootstrap';
import { ComposableMap, Geographies, Geography, ProjectionConfig, ZoomableGroup } from 'react-simple-maps';
import * as yup from 'yup';
import Auth from '../../components/auth';
import { RenameEvent } from '../../components/editname';
import InfoTip from '../../components/infotip';
import Typeahead from '../../components/Typeahead';
import useAdmin from '../../hooks/useadmin';
import { AdminFormFields } from '../../hooks/useAPIs';
import { extractQueryParam } from '../../libs/api/apipage';
import {
    GallApi,
    GallHost,
    GallHostUpdateFields,
    PlaceNoTreeApi,
    SimpleSpecies,
    SpeciesWithPlaces,
} from '../../libs/api/apitypes';
import { allGalls } from '../../libs/db/gall';
import { allHostsWithPlaces } from '../../libs/db/host';
import Admin from '../../libs/pages/admin';
import { mightFailWithArray } from '../../libs/utils/util';
// needed as ReactTooltip does not play nicely with SSR. See: https://github.com/wwayne/react-tooltip/issues/675
import dynamic from 'next/dynamic';

const ReactTooltip = dynamic(() => import('react-tooltip'), {
    ssr: false,
});

type Props = {
    id: string;
    galls: GallApi[];
    hosts: SpeciesWithPlaces[];
};

const schema = yup.object().shape({
    mainField: yup.array().required('You must provide the gall.'),
});

type FormFields = AdminFormFields<GallApi> & {
    hosts: GallHost[];
    places: PlaceNoTreeApi[];
};

const update = async (s: GallApi, e: RenameEvent) => ({
    ...s,
    name: e.new,
});

const fetchGallHosts = async (id: number | undefined): Promise<SpeciesWithPlaces[]> => {
    if (id == undefined) return [];

    const res = await fetch(`../api/gallhost?gallid=${id}`);
    if (res.status === 200) {
        return (await res.json()) as SpeciesWithPlaces[];
    } else {
        console.error(await res.text());
        throw new Error('Failed to fetch host for the selected gall. Check console.');
    }
};

const projConfig: ProjectionConfig = {
    center: [-4, 48],
    parallels: [29.5, 45.5],
    rotate: [96, 0, 0],
    scale: 750,
};

const GallHostMapper = ({ id, galls, hosts }: Props): JSX.Element => {
    const [gallHosts, setGallHosts] = useState<Array<SpeciesWithPlaces>>([]);
    const [inRange, setInRange] = useState<Map<string, PlaceNoTreeApi>>(new Map());
    const [outRange, setOutRange] = useState<Map<string, PlaceNoTreeApi>>(new Map());
    const [tooltipContent, setTooltipContent] = useState('');

    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    const toUpsertFields = (fields: FormFields, name: string, id: number): GallHostUpdateFields => {
        return {
            gall: id,
            hosts: gallHosts.map((h) => h.id),
            // just grab the ones that have been excluded
            rangeExclusions: [...outRange.values()],
        };
    };

    const updatedFormFields = async (gall: GallApi | undefined): Promise<FormFields> => {
        if (gall != undefined) {
            const hosts = gallHosts.length <= 0 ? await fetchGallHosts(gall.id) : gallHosts;
            setGallHosts(hosts);

            return {
                mainField: [gall],
                hosts: hosts,
                places: [],
                del: false,
            };
        }

        setSelected(gall);

        return {
            mainField: [],
            hosts: [],
            places: [],
            del: false,
        };
    };

    // eslint-disable-next-line prettier/prettier
    const {
        selected,
        setSelected,
        error,
        setError,
        deleteResults,
        setDeleteResults,
        form,
        formSubmit,
        mainField,
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

    const selectAll = () => {
        const m = new Map<string, PlaceNoTreeApi>();
        gallHosts.flatMap((gh) => gh.places).forEach((p) => m.set(p.code, p));
        setInRange(m);
        setOutRange(new Map());
    };

    const deselectAll = () => {
        const m = new Map<string, PlaceNoTreeApi>();
        gallHosts.flatMap((gh) => gh.places).forEach((p) => m.set(p.code, p));
        setOutRange(m);
        setInRange(new Map());
    };

    useEffect(() => {
        if (selected && gallHosts.length > 0) {
            const possibleRange = new Map<string, PlaceNoTreeApi>();
            gallHosts.flatMap((gh) => gh.places).forEach((p) => possibleRange.set(p.code, p));

            // create the set of excluded places
            const outOfRange = new Map<string, PlaceNoTreeApi>();
            // handle when a host is removed and the possible range has shrunk
            selected.excludedPlaces = selected.excludedPlaces.filter((p) => possibleRange.has(p.code));
            selected.excludedPlaces.forEach((p) => outOfRange.set(p.code, p));
            setOutRange(outOfRange);

            const inTheRange = new Map<string, PlaceNoTreeApi>();
            gallHosts
                .flatMap((gh) => gh.places)
                .forEach((p) => {
                    if (!outOfRange.has(p.code)) {
                        inTheRange.set(p.code, p);
                    }
                });
            setInRange(inTheRange);
        } else {
            setInRange(new Map());
            setOutRange(new Map());
        }
    }, [gallHosts, selected]);

    return (
        <Auth>
            <Admin
                type="Gallhost"
                keyField="name"
                setError={setError}
                error={error}
                setDeleteResults={setDeleteResults}
                deleteResults={deleteResults}
                selected={selected}
            >
                <form onSubmit={form.handleSubmit(formSubmit)} className="m-4 pr-4">
                    <h4>Gall - Host Mappings</h4>
                    <p>
                        First select a gall. If any mappings to hosts already exist they will show up in the Host field. Then you
                        can edit these mappings (add or delete).
                    </p>
                    <p>
                        At least one host species must exist before mapping.{' '}
                        <Link href="./host">
                            <a>Go add one</a>
                        </Link>{' '}
                        now if you need to.
                    </p>
                    <Row className="form-group">
                        <Col>
                            Gall:
                            {mainField('name', 'Gall')}
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
                            <Typeahead
                                name="hosts"
                                control={form.control}
                                placeholder="Hosts"
                                options={hosts}
                                labelKey="name"
                                multiple
                                clearButton
                                disabled={!selected}
                                selected={gallHosts ? gallHosts : []}
                                onChange={(s) => {
                                    setGallHosts(s);
                                }}
                            />
                            {form.formState.errors.hosts && (
                                <span className="text-danger">You must map at least one host to this gall.</span>
                            )}
                        </Col>
                    </Row>
                    <Row className="form-group">
                        <Col>
                            Range:
                            <InfoTip
                                id="range-help"
                                text="By default the range for a gall is the union of all places that the selected Hosts occur in. It is not
                            always true that a Gall will occur in the area where a Host occurs. Click on the Places below to
                            add/remove them from the Gall's range. Do not exclude places based solely on a lack of known observations. 
                            Remove places when a gall is known only at a genus or section level in one area (eg CA) and unlikely to be found 
                            on members of that taxon in other areas (eg eastern NA), or when a clear and unambiguous geographic pattern 
                            exists for a species of which observations are numerous. When in doubt, leave every place where a host occurs."
                            />
                            <ComposableMap
                                className="border"
                                projection="geoConicEqualArea"
                                projectionConfig={projConfig}
                                data-tip=""
                            >
                                <ZoomableGroup zoom={1} minZoom={0.75}>
                                    <Geographies geography="../usa-can-topo.json">
                                        {({ geographies }) =>
                                            geographies.map((geo) => {
                                                const code = geo.properties.postal;
                                                return (
                                                    <Geography
                                                        key={geo.rsmKey}
                                                        geography={geo}
                                                        stroke={'DarkSlateGray'}
                                                        fill={
                                                            outRange.has(code)
                                                                ? 'LightCoral'
                                                                : inRange.has(code)
                                                                ? 'ForestGreen'
                                                                : 'White'
                                                        }
                                                        style={{
                                                            default: { outline: 'none' },
                                                            hover: { outline: 'none' },
                                                            pressed: { outline: 'none' },
                                                        }}
                                                        onClick={() => {
                                                            let p = inRange.get(code);
                                                            if (p) {
                                                                outRange.set(code, p);
                                                                setOutRange(new Map(outRange));
                                                                inRange.delete(code);
                                                                setInRange(new Map(inRange));
                                                            } else if ((p = outRange.get(code))) {
                                                                inRange.set(code, p);
                                                                setOutRange(new Map(inRange));
                                                                outRange.delete(code);
                                                                setOutRange(new Map(outRange));
                                                            }
                                                        }}
                                                        onMouseEnter={() => setTooltipContent(code)}
                                                        onMouseLeave={() => setTooltipContent('')}
                                                    />
                                                );
                                            })
                                        }
                                    </Geographies>
                                </ZoomableGroup>
                            </ComposableMap>
                            <ReactTooltip>{tooltipContent}</ReactTooltip>
                        </Col>
                    </Row>
                    <Row className="form-group">
                        <Col>
                            <Button variant="outline-secondary" size="sm" className="mr-2" onClick={selectAll}>
                                Select All
                            </Button>
                            <Button variant="outline-secondary" size="sm" onClick={deselectAll}>
                                De-select All
                            </Button>
                        </Col>
                        <Col className="text-right">
                            <span className="border p-2 m-1" style={{ borderRadius: '5px', backgroundColor: 'ForestGreen' }}>
                                Gall & Host
                            </span>
                            <span className="border p-2 m-1" style={{ borderRadius: '5px', backgroundColor: 'LightCoral' }}>
                                Host Only
                            </span>
                            <span className="border p-2 m-1" style={{ borderRadius: '5px', backgroundColor: 'White' }}>
                                Neither
                            </span>
                        </Col>
                    </Row>
                    <Row className="form-group">
                        <Col>
                            <input type="submit" className="button" value="Submit" disabled={!selected || gallHosts.length < 1} />
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

    return {
        props: {
            id: id,
            galls: await mightFailWithArray<GallApi>()(allGalls()),
            hosts: await mightFailWithArray<SimpleSpecies>()(allHostsWithPlaces()),
        },
    };
};

export default GallHostMapper;
