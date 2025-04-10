import { constant, constFalse, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetServerSideProps } from 'next';
import { useSession } from 'next-auth/react';
import Head from 'next/head';
import Link from 'next/link';
import { useRouter } from 'next/router';
import { ParsedUrlQuery } from 'querystring';
import { useEffect, useState } from 'react';
import { Alert, Badge, Button, Card, Col, Container, Form, OverlayTrigger, Popover, Row } from 'react-bootstrap';
import { Typeahead } from 'react-bootstrap-typeahead';
import { Controller, useForm } from 'react-hook-form';
import Edit from '../components/edit';
import InfoTip from '../components/infotip';
import { getQueryParams } from '../libs/api/apipage';
import {
    DetachableApi,
    detachableFromString,
    DetachableNone,
    Detachables,
    EMPTYSEARCHQUERY,
    FilterField,
    GallIDApi,
    HostSimple,
    PlaceApi,
    SearchQuery,
    TaxonCodeValues,
    TaxonomyEntry,
    TaxonomyEntryNoParent,
    TaxonomyTypeValues,
} from '../libs/api/apitypes';
import {
    getAlignments,
    getCells,
    getColors,
    getForms,
    getLocations,
    getSeasons,
    getShapes,
    getTextures,
    getWalls,
} from '../libs/db/filterfield';
import { allHostsSimple } from '../libs/db/host';
import { getPlaces } from '../libs/db/place.ts';
import { allGenera, allSections } from '../libs/db/taxonomy';
import { createSummary, defaultImage, formatWithDescription } from '../libs/pages/renderhelpers';
import { checkGall, GALL_FORM, LEAF_ANYWHERE } from '../libs/utils/gallsearch.ts';
import { capitalizeFirstLetter, hasProp, mightFailWithArray } from '../libs/utils/util';

type SearchFormHostField = {
    host: HostSimple[];
    genus?: never;
};

type SearchFormGenusField = {
    host?: never;
    genus: TaxonomyEntryNoParent[];
};

type SearchFormFields = SearchFormHostField | SearchFormGenusField;

type FilterFormFields = {
    locations: string[];
    detachable: DetachableApi[];
    textures: string[];
    alignment: string;
    walls: string;
    cells: string;
    shape: string;
    color: string;
    season: string;
    form: string;
    undescribed: boolean;
    place: string[];
    family: string;
};

// const invalidArraySelection = (arr: unknown[]) => {
//     return arr?.length === 0;
// };

const isTaxonomy = (o: unknown): o is TaxonomyEntryNoParent => hasProp(o, 'type');
const isHost = (o: unknown): o is HostSimple => hasProp(o, 'datacomplete') && hasProp(o, 'aliases');

// const Schema = t.union([
//     t.type({
//         host: t.array(TaxonomyEntryNoParentSchema),
//     }),
//     t.type({
//         genus: t.array(HostSimpleSchema),
//     }),
// ]);

// const Schema = yup.object().shape(
//     {
//         host: yup.array().when('genus', {
//             is: invalidArraySelection,
//             then: yup.array().required('You must provide a search,'),
//             otherwise: yup.array(),
//         }),
//         genus: yup.array().when('host', {
//             is: invalidArraySelection,
//             then: yup.array().required('You must provide a search,'),
//             otherwise: yup.array(),
//         }),
//     },
//     [['host', 'genus']],
// );

type Props = {
    hostOrTaxon: TaxonomyEntryNoParent | HostSimple | undefined | null;
    query: SearchQuery | null;
    hosts: HostSimple[];
    sectionsAndGenera: TaxonomyEntryNoParent[];
    locations: FilterField[];
    colors: FilterField[];
    seasons: FilterField[];
    shapes: FilterField[];
    textures: FilterField[];
    alignments: FilterField[];
    walls: FilterField[];
    cells: FilterField[];
    forms: FilterField[];
    places: PlaceApi[];
};

const convertQForUrl = (hostOrTaxon: TaxonomyEntryNoParent | HostSimple | undefined, q: SearchQuery | undefined | null) => ({
    hostOrTaxon: hostOrTaxon?.name,
    type: isTaxonomy(hostOrTaxon) ? hostOrTaxon.type : 'host',
    ...(q
        ? {
              detachable: q.detachable[0].value,
              alignment: q.alignment.join(','),
              cells: q.cells.join(','),
              color: q.color.join(','),
              locations: q.locations.join(','),
              season: q.season.join(','),
              shape: q.shape.join(','),
              textures: q.textures.join(','),
              walls: q.walls.join(','),
              form: q.form.join(','),
              undescribed: q.undescribed,
              place: q.place,
              family: q.family,
          }
        : null),
});

const isHostComplete = (hostOrTaxon: TaxonomyEntryNoParent | HostSimple | null | undefined) => {
    return isHost(hostOrTaxon) && hostOrTaxon.datacomplete;
};

const IDGall = (props: Props): JSX.Element => {
    const [galls, setGalls] = useState(new Array<GallIDApi>());
    const [filtered, setFiltered] = useState(new Array<GallIDApi>());
    const [hostOrTaxon, setHostOrTaxon] = useState(props?.hostOrTaxon);
    const [query, setQuery] = useState(props.query);
    const [gallFamilies, setGallFamilies] = useState(new Array<string>());

    const [showAdvanced, setShowAdvanced] = useState(
        (props.query?.alignment?.length ?? -1) > 0 ||
            (props.query?.cells?.length ?? -1) > 0 ||
            (props.query?.color?.length ?? -1) > 0 ||
            (props.query?.form?.length ?? -1) > 0 ||
            (props.query?.season?.length ?? -1) > 0 ||
            (props.query?.shape?.length ?? -1) > 0 ||
            (props.query?.textures?.length ?? -1) > 0 ||
            (props.query?.walls?.length ?? -1) > 0 ||
            props.query?.undescribed,
    );

    const advancedHasSelection = () => {
        return (
            (query?.alignment && query?.alignment.length > 0) ||
            (query?.cells && query?.cells.length > 0) ||
            (query?.color && query?.color.length > 0) ||
            (query?.form && query?.form.length > 0) ||
            (query?.season && query?.season.length > 0) ||
            (query?.shape && query?.shape.length > 0) ||
            (query?.textures && query?.textures.length > 0) ||
            (query?.walls && query?.walls.length > 0) ||
            query?.undescribed
        );
    };

    const disableFilter = (): boolean => {
        return !hostOrTaxon;
    };

    // this is the search form on species or genus
    const {
        formState: { errors },
        control: taxonControl,
    } = useForm<SearchFormFields>({
        mode: 'onBlur',
        // resolver: yupResolver(Schema),
    });

    const router = useRouter();
    const { data: session } = useSession();

    // this is the faceted filter form
    const { control: filterControl, reset: resetFilter } = useForm<FilterFormFields>();

    const resetForm = () => {
        setQuery(null);
        setHostOrTaxon(undefined);
        setFiltered([]);
    };

    useEffect(() => {
        const fetchData = async () => {
            if (!hostOrTaxon) {
                resetFilter();
                setGalls([]);
                setFiltered([]);
                void router.replace('', undefined, { shallow: true });

                return;
            }

            try {
                let queryString = '';
                if (isTaxonomy(hostOrTaxon)) {
                    if (hostOrTaxon.type === TaxonomyTypeValues.SECTION) {
                        queryString = `?section=${hostOrTaxon.name}`;
                    } else {
                        queryString = `?genus=${hostOrTaxon.name}`;
                    }
                } else {
                    queryString = encodeURI(`?host=${hostOrTaxon.name}`);
                }

                const res = await fetch(`../api/search${queryString}`, {
                    method: 'GET',
                });

                if (res.status === 200) {
                    const g = (await res.json()) as GallIDApi[];
                    if (!g || !Array.isArray(g)) {
                        throw new Error('Received an invalid search result.');
                    }
                    setGalls(g.sort((a, b) => a.name.localeCompare(b.name)));
                    setFiltered(g);
                    setGallFamilies([...new Set(g.map((gg) => gg.family))].sort());

                    void router.replace(
                        {
                            query: {
                                ...convertQForUrl(hostOrTaxon, query),
                            },
                        },
                        undefined,
                        { shallow: true },
                    );
                } else {
                    throw new Error(await res.text());
                }
            } catch (e) {
                console.error(e);
            }
        };

        void fetchData();
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [hostOrTaxon]);

    useEffect(() => {
        if (!query || !hostOrTaxon) {
            void router.replace('', undefined, { shallow: true });
            return;
        }

        const f = galls.filter((g) => checkGall(g, query));
        setFiltered(f);

        void router.replace(
            {
                query: {
                    ...convertQForUrl(hostOrTaxon, query),
                },
            },
            undefined,
            { shallow: true },
        );
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [query, galls]);

    const makeFormInput = (
        field: keyof Omit<FilterFormFields, 'detachable' | 'undescribed'>,
        opts: string[],
        multiple = false,
    ) => {
        return (
            <Controller
                name={field}
                control={filterControl}
                render={() => (
                    <Typeahead
                        id={field}
                        selected={query ? query[field] : []}
                        onChange={(selected) => {
                            setQuery({
                                ...(query ? query : EMPTYSEARCHQUERY),
                                [field]: selected,
                            });
                        }}
                        placeholder={capitalizeFirstLetter(field)}
                        options={opts}
                        disabled={disableFilter()}
                        clearButton={true}
                        multiple={multiple}
                    />
                )}
            />
            // <Typeahead
            //     id={field}
            //     control={filterControl}
            //     selected={query ? query[field] : []}
            //     onChange={(selected) => {
            //         setQuery({
            //             ...(query ? query : EMPTYSEARCHQUERY),
            //             [field]: selected,
            //         });
            //     }}
            //     placeholder={capitalizeFirstLetter(field)}
            //     options={opts}
            //     disabled={disableFilter()}
            //     clearButton={true}
            //     multiple={multiple}
            // />
        );
    };

    return (
        <Container className="m-2" fluid>
            <Head>
                <title>ID Galls</title>
                <meta name="description" content="A tool for IDing galls on host plants." />
            </Head>

            <Row className="">
                <Col>
                    <form>
                        <Row>
                            <Col sm={12} md={5}>
                                <Form.Label>Host:</Form.Label>
                                <Controller
                                    name="host"
                                    control={taxonControl}
                                    render={() => (
                                        <Typeahead
                                            id="host"
                                            selected={hostOrTaxon && isHost(hostOrTaxon) ? [hostOrTaxon] : []}
                                            onChange={(h) => {
                                                setHostOrTaxon(h[0] as HostSimple);
                                                // clear the Place if any
                                                if (query) query.place = [];
                                            }}
                                            placeholder="Host"
                                            clearButton
                                            options={props.hosts}
                                            labelKey={(h) => {
                                                const host = h as HostSimple;
                                                if (host) {
                                                    const aliases = host.aliases
                                                        .map((a) => a.name)
                                                        .sort()
                                                        .join(', ');
                                                    return aliases.length > 0 ? `${host.name} (${aliases})` : host.name;
                                                } else {
                                                    return '';
                                                }
                                            }}
                                        />
                                    )}
                                />
                                {/* <Typeahead
                                    name="host"
                                    control={control}
                                    selected={hostOrTaxon && isHost(hostOrTaxon) ? [hostOrTaxon] : []}
                                    onChange={(h) => {
                                        setHostOrTaxon(h[0] as HostSimple);
                                        // clear the Place if any
                                        if (query) query.place = [];
                                    }}
                                    placeholder="Host"
                                    clearButton
                                    options={props.hosts}
                                    labelKey={(h) => {
                                        const host = h as HostSimple;
                                        if (host) {
                                            const aliases = host.aliases
                                                .map((a) => a.name)
                                                .sort()
                                                .join(', ');
                                            return aliases.length > 0 ? `${host.name} (${aliases})` : host.name;
                                        } else {
                                            return '';
                                        }
                                    }}
                                /> */}
                            </Col>
                            <Col sm={12} md={1} className="align-self-end text-center my-2">
                                OR
                            </Col>
                            <Col sm={12} md={5}>
                                <Form.Label>Genus / Section:</Form.Label>
                                <Controller
                                    name="genus"
                                    control={taxonControl}
                                    render={() => (
                                        <Typeahead
                                            id="genus"
                                            selected={hostOrTaxon && isTaxonomy(hostOrTaxon) ? [hostOrTaxon] : []}
                                            onChange={(g) => {
                                                setHostOrTaxon(g[0] as TaxonomyEntryNoParent);
                                            }}
                                            placeholder="Genus"
                                            clearButton
                                            options={props.sectionsAndGenera}
                                            labelKey={(t) => {
                                                const tax = t as TaxonomyEntryNoParent;
                                                if (tax) {
                                                    return formatWithDescription(tax.name, tax.description);
                                                } else {
                                                    return '';
                                                }
                                            }}
                                        />
                                    )}
                                />
                                {/* <Typeahead
                                    name="genus"
                                    control={control}
                                    selected={hostOrTaxon && isTaxonomy(hostOrTaxon) ? [hostOrTaxon] : []}
                                    onChange={(g) => {
                                        setHostOrTaxon(g[0] as TaxonomyEntryNoParent);
                                    }}
                                    placeholder="Genus"
                                    clearButton
                                    options={props.sectionsAndGenera}
                                    labelKey={(t) => {
                                        const tax = t as TaxonomyEntryNoParent;
                                        if (tax) {
                                            return formatWithDescription(tax.name, tax.description);
                                        } else {
                                            return '';
                                        }
                                    }}
                                /> */}
                            </Col>
                            <Col>
                                <OverlayTrigger
                                    placement="auto"
                                    trigger="click"
                                    rootClose
                                    overlay={
                                        <Popover id="help">
                                            <Popover.Header>Gall ID Help</Popover.Header>
                                            <Popover.Body>
                                                <p>
                                                    First select either the host species or the genus/section for a host. If you
                                                    need help IDing the host try{' '}
                                                    <a href="https://www.inaturalist.org" target="_blank" rel="noreferrer">
                                                        iNaturalist.
                                                    </a>{' '}
                                                    You can then filter the found galls using the boxes below. See the{' '}
                                                    <Link href="/filterguide">Gall Filter Term Guide</Link> for more details.
                                                </p>
                                                <p>
                                                    Note: that leaving a field blank doesn’t exclude any galls, whether they have
                                                    values in that field or not. Choosing one or more values in a field removes
                                                    all galls that don’t include at least those values.
                                                </p>
                                            </Popover.Body>
                                        </Popover>
                                    }
                                >
                                    <Badge bg="secondary" className="m-1">
                                        ?
                                    </Badge>
                                </OverlayTrigger>
                            </Col>
                        </Row>
                        <Row>
                            <Col>
                                {(errors.genus || errors.host) && (
                                    <span className="text-danger">
                                        You must provide a search selection, either a Host species or genus.
                                    </span>
                                )}
                            </Col>
                        </Row>
                    </form>
                </Col>
            </Row>
            <Row>
                <Col>
                    <hr />
                </Col>
            </Row>
            {/* The filters */}
            <Row className="">
                <Col>
                    <Form>
                        {/* Always visibile filters */}
                        <Row className="d-flex">
                            <Col sm={12} md={6} lg={3} className="flex-fill">
                                <Form.Label>
                                    Location(s):
                                    <InfoTip id="locationstip" text="Where on the host the gall is found." />
                                </Form.Label>
                                <Controller
                                    name="locations"
                                    control={filterControl}
                                    render={() => (
                                        <Typeahead
                                            id="locations"
                                            selected={query ? query.locations : []}
                                            onChange={(s) => {
                                                const selected = s as string[];
                                                setQuery({
                                                    ...(query ? query : EMPTYSEARCHQUERY),
                                                    locations: selected,
                                                });
                                            }}
                                            placeholder="Locations"
                                            options={props.locations
                                                .map((l) => l.field)
                                                .concat(LEAF_ANYWHERE)
                                                .sort()}
                                            disabled={disableFilter()}
                                            clearButton={true}
                                            multiple={true}
                                        />
                                    )}
                                />
                                {/* <Typeahead
                                    name="locations"
                                    control={filterControl}
                                    selected={query ? query.locations : []}
                                    onChange={(s) => {
                                        const selected = s as string[];
                                        setQuery({
                                            ...(query ? query : EMPTYSEARCHQUERY),
                                            locations: selected,
                                        });
                                    }}
                                    placeholder="Locations"
                                    options={props.locations
                                        .map((l) => l.field)
                                        .concat(LEAF_ANYWHERE)
                                        .sort()}
                                    disabled={disableFilter()}
                                    clearButton={true}
                                    multiple={true}
                                /> */}
                            </Col>
                            <Col sm={12} md={6} lg={3}>
                                <Form.Label>
                                    Detachable:
                                    <InfoTip id="detachabletip" text="Can the gall be removed from the host without cutting?" />
                                </Form.Label>
                                <Controller
                                    name="detachable"
                                    control={filterControl}
                                    render={() => (
                                        <Typeahead
                                            id="detachable"
                                            selected={query ? query.detachable : []}
                                            onChange={(s) => {
                                                const selected = s as DetachableApi[];
                                                setQuery({
                                                    ...(query ? query : EMPTYSEARCHQUERY),
                                                    detachable: selected.length > 0 ? selected : [DetachableNone],
                                                });
                                            }}
                                            options={Detachables}
                                            labelKey={'value'}
                                            disabled={disableFilter()}
                                            clearButton={true}
                                        />
                                    )}
                                />
                                {/* <Typeahead
                                    name="detachable"
                                    control={filterControl}
                                    selected={query ? query.detachable : []}
                                    onChange={(s) => {
                                        const selected = s as DetachableApi[];
                                        setQuery({
                                            ...(query ? query : EMPTYSEARCHQUERY),
                                            detachable: selected.length > 0 ? selected : [DetachableNone],
                                        });
                                    }}
                                    options={Detachables}
                                    labelKey={'value'}
                                    disabled={disableFilter()}
                                    clearButton={true}
                                /> */}
                            </Col>
                            <Col sm={12} md={6} lg={3}>
                                <Form.Label>
                                    Place:
                                    <InfoTip id="placetip" text="Where did you see the Gall? (US states or CAN provinces)." />
                                </Form.Label>
                                <Controller
                                    name="place"
                                    control={filterControl}
                                    render={() => (
                                        <Typeahead
                                            id="place"
                                            selected={query ? query.place : []}
                                            onChange={(s) => {
                                                const selected = s as string[];
                                                setQuery({
                                                    ...(query ? query : EMPTYSEARCHQUERY),
                                                    place: selected.length > 0 ? selected : [],
                                                });
                                            }}
                                            options={props.places.map((p) => p.name)}
                                            disabled={disableFilter()}
                                            clearButton={true}
                                        />
                                    )}
                                />
                                {/* <Typeahead
                                    name="place"
                                    control={filterControl}
                                    selected={query ? query.place : []}
                                    onChange={(s) => {
                                        const selected = s as string[];
                                        setQuery({
                                            ...(query ? query : EMPTYSEARCHQUERY),
                                            place: selected.length > 0 ? selected : [],
                                        });
                                    }}
                                    options={props.places.map((p) => p.name)}
                                    disabled={disableFilter()}
                                    clearButton={true}
                                /> */}
                            </Col>
                            <Col sm={12} md={6} lg={3}>
                                <Form.Label>
                                    Gall Family:
                                    <InfoTip id="familytip" text="The taxonomic Family of the Gallformer." />
                                </Form.Label>
                                <Controller
                                    name="family"
                                    control={filterControl}
                                    render={() => (
                                        <Typeahead
                                            id="family"
                                            selected={query ? query.family : []}
                                            onChange={(s) => {
                                                const selected = s as string[];
                                                setQuery({
                                                    ...(query ? query : EMPTYSEARCHQUERY),
                                                    family: selected.length > 0 ? selected : [],
                                                });
                                            }}
                                            options={gallFamilies}
                                            disabled={disableFilter()}
                                            clearButton={true}
                                        />
                                    )}
                                />
                                {/* <Typeahead
                                    name="family"
                                    control={filterControl}
                                    selected={query ? query.family : []}
                                    onChange={(s) => {
                                        const selected = s as string[];
                                        setQuery({
                                            ...(query ? query : EMPTYSEARCHQUERY),
                                            family: selected.length > 0 ? selected : [],
                                        });
                                    }}
                                    options={gallFamilies}
                                    disabled={disableFilter()}
                                    clearButton={true}
                                /> */}
                            </Col>
                        </Row>
                        <Row>
                            <Col xs={12}>
                                <Row>
                                    <Col className="pt-2">
                                        <Button
                                            variant="outline-primary"
                                            size="sm"
                                            onClick={() => setShowAdvanced(!showAdvanced)}
                                        >
                                            {showAdvanced ? 'Hide Advanced Filters' : 'Show Advanced Filters'}
                                        </Button>
                                        {!showAdvanced && advancedHasSelection() && (
                                            <p className="text-danger small">You have active selections in the hidden filters.</p>
                                        )}
                                    </Col>
                                    <Col className="pt-2 d-flex justify-content-end">
                                        <Button variant="outline-danger" size="sm" onClick={resetForm}>
                                            Clear All Filters
                                        </Button>
                                    </Col>
                                </Row>
                            </Col>
                        </Row>
                        <Row hidden={!showAdvanced}>
                            <Col xs={12}>
                                <hr />
                                <p className="small">
                                    <em>
                                        Be aware that many galls do not have associated information for all of the below
                                        properties.
                                    </em>
                                </p>
                            </Col>
                        </Row>
                        <Row hidden={!showAdvanced}>
                            <Col>
                                <Row className="pb-3">
                                    <Col xs={12} sm={6} md={3}>
                                        <Form.Label>
                                            Season: <InfoTip id="seasons" text="The season when the gall first appears." />
                                        </Form.Label>
                                        {makeFormInput(
                                            'season',
                                            props.seasons.map((c) => c.field),
                                        )}
                                    </Col>
                                    <Col xs={12} sm={6} md={3}>
                                        <Form.Label>
                                            Texture(s):
                                            <InfoTip id="textures" text="The look and feel of the gall." />
                                        </Form.Label>
                                        {makeFormInput(
                                            'textures',
                                            props.textures.map((t) => t.field),
                                            true,
                                        )}
                                    </Col>
                                    <Col xs={12} sm={6} md={3}>
                                        <Form.Label>
                                            Alignment:{' '}
                                            <InfoTip
                                                id="alignment"
                                                text="How the gall is positioned relative to the host substrate."
                                            />
                                        </Form.Label>
                                        {makeFormInput(
                                            'alignment',
                                            props.alignments.map((a) => a.field),
                                        )}
                                    </Col>
                                    <Col xs={12} sm={6} md={3}>
                                        <Form.Label>
                                            Form: <InfoTip id="form" text="The overall form of the gall." />
                                        </Form.Label>
                                        {makeFormInput(
                                            'form',
                                            props.forms
                                                .map((c) => c.field)
                                                .concat(GALL_FORM)
                                                .sort(),
                                        )}
                                    </Col>
                                </Row>
                                <Row>
                                    <Col xs={12} sm={6} md={3}>
                                        <Form.Label>
                                            Walls:{' '}
                                            <InfoTip
                                                id="walls"
                                                text="What the walls between the outside and the inside of the gall are like."
                                            />
                                        </Form.Label>
                                        {makeFormInput(
                                            'walls',
                                            props.walls.map((w) => w.field),
                                        )}
                                    </Col>
                                    <Col xs={12} sm={6} md={3}>
                                        <Form.Label>
                                            Cells:{' '}
                                            <InfoTip id="cells" text="The number of internal chambers that the gall contains." />
                                        </Form.Label>
                                        {makeFormInput(
                                            'cells',
                                            props.cells.map((c) => c.field),
                                        )}
                                    </Col>
                                    <Col xs={12} sm={6} md={3}>
                                        <Form.Label>
                                            Shape: <InfoTip id="shape" text="The overall shape of the gall." />
                                        </Form.Label>
                                        {makeFormInput(
                                            'shape',
                                            props.shapes.map((s) => s.field),
                                        )}
                                    </Col>
                                    <Col xs={12} sm={6} md={3}>
                                        <Form.Label>
                                            Color: <InfoTip id="color" text="The outside color of the gall." />
                                        </Form.Label>
                                        {makeFormInput(
                                            'color',
                                            props.colors.map((c) => c.field),
                                        )}
                                    </Col>
                                    <Col xs={12} sm={6} md={3} className="pt-3">
                                        <Form.Label>
                                            Only Undescribed: <InfoTip id="undescribed" text="Show only undescribed galls." />
                                        </Form.Label>
                                        <Controller
                                            control={filterControl}
                                            name="undescribed"
                                            render={({ field: { ref } }) => (
                                                <input
                                                    ref={ref}
                                                    type="checkbox"
                                                    className="form-input-checkbox"
                                                    checked={!!query && query.undescribed}
                                                    onChange={(selected) => {
                                                        setQuery({
                                                            ...(query ? query : EMPTYSEARCHQUERY),
                                                            undescribed: selected.currentTarget.checked,
                                                        });
                                                    }}
                                                />
                                            )}
                                        />
                                    </Col>
                                </Row>
                            </Col>
                        </Row>
                    </Form>
                </Col>
            </Row>
            <Row>
                <Col>
                    <hr />
                </Col>
            </Row>
            {/* Results */}
            {!isHostComplete(hostOrTaxon) && isHost(hostOrTaxon) && (
                <Row className="pt-2">
                    <Col>
                        <Alert variant="warning" className="small ps-2 py-1">
                            This host does not yet have all of the known galls added to the database.
                        </Alert>
                    </Col>
                </Row>
            )}
            <Row className="py-1">
                <Col xs={12} sm={6} md={3}>
                    Showing {filtered.length} of {galls.length} galls:
                </Col>
            </Row>
            <Row className="">
                <Col>
                    <Row>
                        {filtered.map((g) => {
                            const summary = createSummary(g);
                            return (
                                <Col key={g.id.toString() + 'col'} xs={6} md={3} className="pb-2">
                                    <Card key={g.id} border="secondary">
                                        <Link href={`gall/${g.id}`}>
                                            <Card.Img
                                                variant="top"
                                                src={defaultImage(g)?.small ? defaultImage(g)?.small : '/images/noimage.jpg'}
                                                alt={`${g.name} - ${summary}`}
                                            />
                                        </Link>
                                        <Card.Body>
                                            <Card.Title>
                                                <Link href={`gall/${g.id}`} className="small">
                                                    {g.name}
                                                </Link>
                                            </Card.Title>
                                            <Card.Text className="small">
                                                {!defaultImage(g) && summary}
                                                {session && (
                                                    <span className="p-0 pe-1 my-auto">
                                                        <Edit id={g.id} type="gall" />
                                                        {g.datacomplete ? '💯' : '❓'}
                                                    </span>
                                                )}
                                            </Card.Text>
                                        </Card.Body>
                                    </Card>
                                </Col>
                            );
                        })}
                    </Row>
                </Col>
            </Row>
            <Row className="">
                <Col>
                    {filtered.length == 0 ? (
                        hostOrTaxon == undefined ? (
                            <Alert variant="primary" className="small">
                                To begin with select a Host or a Genus to see matching galls. Then you can use the filters to
                                narrow down the list.
                            </Alert>
                        ) : (
                            <Alert variant="primary" className="small">
                                There are no galls that match your filter. It’s possible there are no described species that fit
                                this set of traits and your gall is undescribed. However, before giving up, try{' '}
                                <Link href="ref/IDGuide#troubleshooting">altering your filter choices</Link>.{' '}
                                {isHostComplete(hostOrTaxon) && (
                                    <span>
                                        To our knowledge, every gall that occurs on the host you have selected is included in the
                                        database. If you find a gall on this host that is not listed above,{' '}
                                        <a href="mailto:gallformers@gmail.com">contact us</a>.
                                    </span>
                                )}
                            </Alert>
                        )
                    ) : (
                        <Alert variant="primary" className="small">
                            If none of these results match your gall, you may have found an undescribed species. However, before
                            concluding that your gall is not in the database, try{' '}
                            <Link href="ref/IDGuide#troubleshooting">altering your filter choices</Link>.{' '}
                            {isHostComplete(hostOrTaxon) && (
                                <span>
                                    To our knowledge, every gall that occurs on the host you have selected is included in the
                                    database. If you find a gall on this host that is not listed above,{' '}
                                    <a href="mailto:gallformers@gmail.com">contact us</a>.
                                </span>
                            )}
                        </Alert>
                    )}
                </Col>
            </Row>
        </Container>
    );
};

const queryUrlParams = [
    'hostOrTaxon',
    'type',
    'detachable',
    'alignment',
    'walls',
    'locations',
    'textures',
    'color',
    'shape',
    'cells',
    'season',
    'form',
    'undescribed',
    'place',
    'family',
];

// Ideally we would generate this page and serve it statically via getStaticProps and use Incremental Static Regeneration.
// See: https://nextjs.org/docs/basic-features/data-fetching#incremental-static-regeneration
// However, as it stands right now next.js can not support query parameters for static content. This sucks given
// that the query parameters that we have only filter data on the client side.
// It seems like it might be possible to "solve" this by implementing a convoluted approach using URL paths rather than
// query parameters but I think that would introduce a ton of complexity.
// This will likely end up the most frequently accessed page on the site AND the most resource intensive on the server
// (other than Admin pages which will never have a lot of traffic). My guess is that we will revisiting this issue.
export const getServerSideProps: GetServerSideProps = async (context: { query: ParsedUrlQuery }) => {
    const hosts = await mightFailWithArray<HostSimple>()(allHostsSimple());
    const genera = await mightFailWithArray<TaxonomyEntry>()(allGenera(TaxonCodeValues.PLANT));
    const sections = await mightFailWithArray<TaxonomyEntry>()(allSections());
    const sectionsAndGenera = [...genera, ...sections].sort((a, b) => a.name.localeCompare(b.name));
    // console.log(sectionsAndGenera);

    const query = getQueryParams(context.query, queryUrlParams);
    const hostOrTaxon = pipe(
        O.fromNullable(query),
        O.chain((q) =>
            pipe(
                q['hostOrTaxon'],
                O.chain((k) =>
                    pipe(
                        q['type'],
                        O.chain((t) =>
                            O.fromNullable(
                                t === 'host'
                                    ? hosts.find((h) => h.name === k)
                                    : sectionsAndGenera.find((g) => g.name === k && g.type === t),
                            ),
                        ),
                    ),
                ),
            ),
        ),
        O.getOrElseW(constant(null)),
    );
    const split = (a: string): string[] => a.split(',');

    const searchQuery: SearchQuery | null = query
        ? {
              alignment: pipe(query['alignment'], O.fold(constant([]), split)),
              cells: pipe(query['cells'], O.fold(constant([]), split)),
              color: pipe(query['color'], O.fold(constant([]), split)),
              detachable: [pipe(query['detachable'], O.fold(constant(DetachableNone), detachableFromString))],
              locations: pipe(query['locations'], O.fold(constant([]), split)),
              season: pipe(query['season'], O.fold(constant([]), split)),
              shape: pipe(query['shape'], O.fold(constant([]), split)),
              textures: pipe(query['textures'], O.fold(constant([]), split)),
              walls: pipe(query['walls'], O.fold(constant([]), split)),
              form: pipe(query['form'], O.fold(constant([]), split)),
              undescribed: pipe(
                  query['undescribed'],
                  O.map((u) => u === 'true'),
                  O.getOrElse(constFalse),
              ),
              place: pipe(query['place'], O.fold(constant([]), split)),
              family: pipe(query['family'], O.fold(constant([]), split)),
          }
        : null;

    const locations = await mightFailWithArray<FilterField>()(getLocations());
    const colors = await mightFailWithArray<FilterField>()(getColors());
    const seasons = await mightFailWithArray<FilterField>()(getSeasons());
    const shapes = await mightFailWithArray<FilterField>()(getShapes());
    const textures = await mightFailWithArray<FilterField>()(getTextures());
    const alignments = await mightFailWithArray<FilterField>()(getAlignments());
    const walls = await mightFailWithArray<FilterField>()(getWalls());
    const cells = await mightFailWithArray<FilterField>()(getCells());
    const forms = await mightFailWithArray<FilterField>()(getForms());
    const places = await mightFailWithArray<PlaceApi>()(getPlaces());

    return {
        props: {
            hostOrTaxon: hostOrTaxon,
            query: searchQuery,
            hosts: hosts,
            sectionsAndGenera: sectionsAndGenera,
            locations: locations,
            colors: colors,
            seasons: seasons,
            shapes: shapes,
            textures: textures,
            alignments: alignments,
            walls: walls,
            cells: cells,
            forms: forms,
            places: places,
        },
    };
};

export default IDGall;
