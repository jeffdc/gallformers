import axios from 'axios';
import * as O from 'fp-ts/lib/Option';
import { constant, pipe } from 'fp-ts/lib/function';
import * as t from 'io-ts';
import { GetServerSideProps } from 'next';
import Link from 'next/link';
import { ParsedUrlQuery } from 'querystring';
import { useEffect, useState } from 'react';
import { Button, Col, Row } from 'react-bootstrap';
import { ComposableMap, Geographies, Geography, ProjectionConfig, ZoomableGroup } from 'react-simple-maps';
import { Tooltip } from 'react-tooltip';
import Typeahead from '../../components/Typeahead';
import Auth from '../../components/auth';
import { RenameEvent } from '../../components/editname';
import InfoTip from '../../components/infotip';
import { AdminFormFields, adminFormFieldsSchema } from '../../hooks/useAPIs';
import useAdmin from '../../hooks/useadmin';
import { extractQueryParam } from '../../libs/api/apipage';
import {
    GallApi,
    GallApiSchema,
    GallHost,
    GallHostSchema,
    GallHostUpdateFields,
    PlaceNoTreeApi,
    PlaceNoTreeApiSchema,
    SimpleSpecies,
    SpeciesWithPlaces,
} from '../../libs/api/apitypes';
import { gallById } from '../../libs/db/gall';
import { allHostsWithPlaces } from '../../libs/db/host';
import Admin from '../../libs/pages/admin';
import { mightFailWithArray } from '../../libs/utils/util';

type Props = {
    id: string | null;
    sp: GallApi[];
    hosts: SpeciesWithPlaces[];
};

const schema = t.intersection([
    adminFormFieldsSchema(GallApiSchema),
    t.type({ hosts: t.array(GallHostSchema), places: t.array(PlaceNoTreeApiSchema) }),
]);

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

    return axios
        .get<SpeciesWithPlaces[]>(`/api/gallhost?gallid=${id}`)
        .then((res) => res.data)
        .catch((e) => {
            console.error(e.toString());
            throw new Error('Failed to fetch host for the selected gall. Check console.', e);
        });
};

const projConfig: ProjectionConfig = {
    center: [-4, 48],
    parallels: [29.5, 45.5],
    rotate: [96, 0, 0],
    scale: 750,
};

const GallHostMapper = ({ sp, id, hosts }: Props): JSX.Element => {
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
    const { selected, setSelected, error, setError, deleteResults, setDeleteResults, form, formSubmit, mainField } = useAdmin<
        GallApi,
        FormFields,
        GallHostUpdateFields
    >(
        'Gall-Host',
        id ?? undefined,
        update,
        toUpsertFields,
        { keyProp: 'name', delEndpoint: '/api/gallhost/', upsertEndpoint: '/api/gallhost/insert' },
        schema,
        updatedFormFields,
        false,
        undefined,
        sp,
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
                <form onSubmit={form.handleSubmit(formSubmit)} className="m-4 pe-4">
                    <h4>Gall - Host Mappings</h4>
                    <p>
                        First select a gall. If any mappings to hosts already exist they will show up in the Host field. Then you
                        can edit these mappings (add or delete).
                    </p>
                    <p>
                        At least one host species must exist before mapping. <Link href="./host">Go add one</Link> now if you need
                        to.
                    </p>
                    <Row className="my-1">
                        <Col>
                            Gall:
                            {mainField('name', 'Gall', { searchEndpoint: (s) => `../api/gall?q=${s}` })}
                        </Col>
                    </Row>
                    <Row>
                        <Col xs={1} className="p-0 m-0 mx-auto">
                            <h2>⇅</h2>
                        </Col>
                    </Row>
                    <Row className="my-1">
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
                                    setGallHosts(s as SpeciesWithPlaces[]);
                                }}
                            />
                            {form.formState.errors.hosts && (
                                <span className="text-danger">You must map at least one host to this gall.</span>
                            )}
                        </Col>
                    </Row>
                    <Row className="my-2">
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
                        </Col>
                    </Row>
                    <Row className="m-1 border">
                        <Col xs={2}>
                            <Row className="my-2">
                                <Col>Legend:</Col>
                            </Row>
                            <Row className="p-1">
                                <Col
                                    className="border d-flex justify-content-center"
                                    style={{ fontWeight: 'bold', borderRadius: '5px', backgroundColor: 'ForestGreen' }}
                                >
                                    Gall & Host
                                </Col>
                            </Row>
                            <Row className="p-1">
                                <Col
                                    className="border d-flex justify-content-center"
                                    style={{ fontWeight: 'bold', borderRadius: '5px', backgroundColor: 'LightCoral' }}
                                >
                                    Host Only
                                </Col>
                            </Row>
                            <Row className="p-1">
                                <Col
                                    className="border d-flex justify-content-center"
                                    style={{ fontWeight: 'bold', borderRadius: '5px', backgroundColor: 'White' }}
                                >
                                    Neither
                                </Col>
                            </Row>
                            <Row>
                                <Col className="my-2">Map Actions:</Col>
                            </Row>
                            <Row className="my-2">
                                <Col>
                                    <Button variant="outline-secondary" size="sm" className="me-2" onClick={selectAll}>
                                        Select All
                                    </Button>
                                    <Button variant="outline-secondary" size="sm" onClick={deselectAll}>
                                        De-select All
                                    </Button>
                                </Col>
                            </Row>
                        </Col>
                        <Col>
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
                                                        onMouseEnter={() => setTooltipContent(`${code} - ${geo.properties.name}`)}
                                                        onMouseLeave={() => setTooltipContent('')}
                                                    />
                                                );
                                            })
                                        }
                                    </Geographies>
                                </ZoomableGroup>
                            </ComposableMap>
                            <Tooltip>{tooltipContent}</Tooltip>
                        </Col>
                    </Row>
                    <Row className="my-1">
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
    const id = extractQueryParam(context.query, 'id');
    const sp = pipe(
        id,
        O.map(parseInt),
        O.map((id) => mightFailWithArray<GallApi>()(gallById(id))),
        O.getOrElse(constant(Promise.resolve(Array<GallApi>()))),
    );

    return {
        props: {
            id: O.getOrElseW(constant(null))(id),
            sp: await sp,
            hosts: await mightFailWithArray<SimpleSpecies>()(allHostsWithPlaces()),
        },
    };
};

export default GallHostMapper;
