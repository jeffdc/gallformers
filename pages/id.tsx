import { yupResolver } from '@hookform/resolvers/yup';
import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetServerSideProps } from 'next';
import { useSession } from 'next-auth/client';
import Head from 'next/head';
import Link from 'next/link';
import { useRouter } from 'next/router';
import { ParsedUrlQuery } from 'querystring';
import React, { useEffect, useState } from 'react';
import { Alert, Badge, Button, Card, Col, Container, OverlayTrigger, Popover, Row } from 'react-bootstrap';
import { useForm } from 'react-hook-form';
import * as yup from 'yup';
import Edit from '../components/edit';
import InfoTip from '../components/infotip';
import Typeahead from '../components/Typeahead';
import { getQueryParams } from '../libs/api/apipage';
import {
    AlignmentApi,
    CellsApi,
    ColorApi,
    DetachableApi,
    detachableFromString,
    DetachableNone,
    Detachables,
    EMPTYSEARCHQUERY,
    GallApi,
    GallLocation,
    GallTexture,
    HostSimple,
    HostTaxon,
    SearchQuery,
    SeasonApi,
    ShapeApi,
    WallsApi,
} from '../libs/api/apitypes';
import { SECTION, TaxonomyEntry, TaxonomyEntryNoParent } from '../libs/api/taxonomy';
import { getAlignments, getCells, getColors, getLocations, getSeasons, getShapes, getTextures, getWalls } from '../libs/db/gall';
import { allHostsSimple } from '../libs/db/host';
import { allGenera, allSections } from '../libs/db/taxonomy';
import { createSummary, defaultImage } from '../libs/pages/renderhelpers';
import { checkGall, LEAF_ANYWHERE } from '../libs/utils/gallsearch';
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
};

const invalidArraySelection = (arr: unknown[]) => {
    return arr?.length === 0;
};

const isTaxonomy = (o: unknown): o is TaxonomyEntryNoParent => hasProp(o, 'type');
const isHost = (o: unknown): o is HostSimple => hasProp(o, 'datacomplete') && hasProp(o, 'aliases');

const Schema = yup.object().shape(
    {
        host: yup.array().when('genus', {
            is: invalidArraySelection,
            then: yup.array().required('You must provide a search,'),
            otherwise: yup.array(),
        }),
        genus: yup.array().when('host', {
            is: invalidArraySelection,
            then: yup.array().required('You must provide a search,'),
            otherwise: yup.array(),
        }),
    },
    [['host', 'genus']],
);

type Props = {
    hostOrTaxon: TaxonomyEntryNoParent | HostSimple | undefined | null;
    query: SearchQuery | null;
    hosts: HostSimple[];
    sectionsAndGenera: TaxonomyEntryNoParent[];
    locations: GallLocation[];
    colors: ColorApi[];
    seasons: SeasonApi[];
    shapes: ShapeApi[];
    textures: GallTexture[];
    alignments: AlignmentApi[];
    walls: WallsApi[];
    cells: CellsApi[];
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
          }
        : null),
});

const isHostComplete = (hostOrTaxon: TaxonomyEntryNoParent | HostSimple | null | undefined) => {
    return isHost(hostOrTaxon) && hostOrTaxon.datacomplete;
};

const IDGall = (props: Props): JSX.Element => {
    const [galls, setGalls] = useState(new Array<GallApi>());
    const [filtered, setFiltered] = useState(new Array<GallApi>());
    const [hostOrTaxon, setHostOrTaxon] = useState(props?.hostOrTaxon);
    const [query, setQuery] = useState(props.query);
    const [showAdvanced, setShowAdvanced] = useState(
        (props.query?.alignment?.length ?? -1) > 0 ||
            (props.query?.cells?.length ?? -1) > 0 ||
            (props.query?.color?.length ?? -1) > 0 ||
            (props.query?.season?.length ?? -1) > 0 ||
            (props.query?.shape?.length ?? -1) > 0 ||
            (props.query?.textures?.length ?? -1) > 0 ||
            (props.query?.walls?.length ?? -1) > 0,
    );

    const advancedHasSelection = () => {
        return (
            (query?.alignment && query?.alignment.length > 0) ||
            (query?.cells && query?.cells.length > 0) ||
            (query?.color && query?.color.length > 0) ||
            (query?.season && query?.season.length > 0) ||
            (query?.shape && query?.shape.length > 0) ||
            (query?.textures && query?.textures.length > 0) ||
            (query?.walls && query?.walls.length > 0)
        );
    };

    const disableFilter = (): boolean => {
        return !hostOrTaxon;
    };

    // this is the search form on species or genus
    const {
        control,
        formState: { errors },
    } = useForm<SearchFormFields>({
        mode: 'onBlur',
        resolver: yupResolver(Schema),
    });

    const router = useRouter();
    const [session] = useSession();

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
                router.replace('', undefined, { shallow: true });

                return;
            }

            try {
                let queryString = '';
                if (isTaxonomy(hostOrTaxon)) {
                    if (hostOrTaxon.type === SECTION) {
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
                    const g = (await res.json()) as GallApi[];
                    if (!g || !Array.isArray(g)) {
                        throw new Error('Received an invalid search result.');
                    }
                    setGalls(g.sort((a, b) => a.name.localeCompare(b.name)));
                    setFiltered(g);

                    router.replace(
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

        fetchData();
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [hostOrTaxon]);

    useEffect(() => {
        if (!query || !hostOrTaxon) {
            router.replace('', undefined, { shallow: true });
            return;
        }

        const f = galls.filter((g) => checkGall(g, query));
        setFiltered(f);

        router.replace(
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

    const makeFormInput = (field: keyof Omit<FilterFormFields, 'detachable'>, opts: string[], multiple = false) => {
        return (
            <Typeahead
                name={field}
                control={filterControl}
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
        );
    };

    return (
        <Container className="m-2" fluid>
            <Head>
                <title>ID Galls</title>
            </Head>

            <Row className="fixed-left pl-2 pt-3 form-group">
                <Col>
                    <form>
                        <Row>
                            <Col sm={12} md={5}>
                                <label className="col-form-label">Host:</label>
                                <Typeahead
                                    name="host"
                                    control={control}
                                    selected={hostOrTaxon && isHost(hostOrTaxon) ? [hostOrTaxon] : []}
                                    onChange={(h) => {
                                        setHostOrTaxon(h[0]);
                                    }}
                                    placeholder="Host"
                                    clearButton
                                    options={props.hosts}
                                    labelKey={(host: HostSimple) => {
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
                            </Col>
                            <Col sm={12} md={1} className="align-self-end my-2">
                                or
                            </Col>
                            <Col sm={12} md={5}>
                                <label className="col-form-label">Genus (Section):</label>
                                <Typeahead
                                    name="genus"
                                    control={control}
                                    selected={hostOrTaxon && isTaxonomy(hostOrTaxon) ? [hostOrTaxon] : []}
                                    onChange={(g) => {
                                        setHostOrTaxon(g[0]);
                                    }}
                                    placeholder="Genus"
                                    clearButton
                                    options={props.sectionsAndGenera}
                                    labelKey={(tax: TaxonomyEntryNoParent) => {
                                        if (tax) {
                                            if (tax.type === SECTION) {
                                                return `${tax.name} - ${tax.description}`;
                                            }
                                            return tax.name;
                                        } else {
                                            return '';
                                        }
                                    }}
                                />
                            </Col>
                            <Col>
                                <OverlayTrigger
                                    placement="auto"
                                    trigger="click"
                                    rootClose
                                    overlay={
                                        <Popover id="help">
                                            <Popover.Title>Gall ID Help</Popover.Title>
                                            <Popover.Content>
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
                                            </Popover.Content>
                                        </Popover>
                                    }
                                >
                                    <Badge variant="info" className="m-1 larger">
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
            <hr />
            {/* The filters */}
            <Row className="fixed-left pl-2 form-group">
                <Col>
                    <form>
                        {/* Always visibile filters */}
                        <Row>
                            <Col sm={12} md={5}>
                                <label className="col-form-label">
                                    Location(s):
                                    <InfoTip id="locations" text="Where on the host the gall is found." />
                                </label>
                                <Typeahead
                                    name="locations"
                                    control={filterControl}
                                    selected={query ? query.locations : []}
                                    onChange={(selected) => {
                                        setQuery({
                                            ...(query ? query : EMPTYSEARCHQUERY),
                                            locations: selected,
                                        });
                                    }}
                                    placeholder="Locations"
                                    options={props.locations
                                        .map((l) => l.loc)
                                        .concat(LEAF_ANYWHERE)
                                        .sort()}
                                    disabled={disableFilter()}
                                    clearButton={true}
                                    multiple={true}
                                />
                            </Col>
                            <Col sm={12} md={4}>
                                <label className="col-form-label">
                                    Detachable:{' '}
                                    <InfoTip id="detachable" text="Can the gall be removed from the host without cutting?" />
                                </label>
                                <Typeahead
                                    name="detachable"
                                    control={filterControl}
                                    selected={query ? query.detachable : []}
                                    onChange={(selected) => {
                                        if (!query) {
                                            return;
                                        }
                                        setQuery({
                                            ...query,
                                            detachable: selected.length > 0 ? selected : [DetachableNone],
                                        });
                                    }}
                                    options={Detachables}
                                    labelKey={'value'}
                                    disabled={disableFilter()}
                                    clearButton={true}
                                />
                            </Col>
                            <Col sm={12} md={3}>
                                <Row>
                                    <Col xs={6} md={12} className="pt-2">
                                        <Button variant="outline-danger" size="sm" onClick={resetForm}>
                                            Clear All Filters
                                        </Button>
                                    </Col>
                                    <Col xs={6} md={12} className="pt-2">
                                        <Button
                                            variant="outline-secondary"
                                            size="sm"
                                            onClick={() => setShowAdvanced(!showAdvanced)}
                                        >
                                            {showAdvanced ? 'Hide Advanced Filters' : 'Show Advanced Filters'}
                                        </Button>
                                        {!showAdvanced && advancedHasSelection() && (
                                            <p className="text-danger small">You have active selections in the hidden filters.</p>
                                        )}
                                    </Col>
                                </Row>
                            </Col>
                        </Row>
                        <Row hidden={!showAdvanced}>
                            <Col xs={12}>
                                <hr />
                                <p className="font-italic small">
                                    Be aware that many galls do not have associated information for all of the below properties.
                                </p>
                            </Col>
                        </Row>
                        <Row hidden={!showAdvanced}>
                            <Col>
                                <label className="col-form-label">
                                    Season: <InfoTip id="seasons" text="The season when the gall first appears." />
                                </label>
                                {makeFormInput(
                                    'season',
                                    props.seasons.map((c) => c.season),
                                )}
                                <label className="col-form-label">
                                    Texture(s):
                                    <InfoTip id="textures" text="The look and feel of the gall." />
                                </label>
                                {makeFormInput(
                                    'textures',
                                    props.textures.map((t) => t.tex),
                                    true,
                                )}
                            </Col>
                            <Col>
                                <label className="col-form-label">
                                    Alignment:{' '}
                                    <InfoTip id="alignment" text="How the gall is positioned relative to the host substrate." />
                                </label>
                                {makeFormInput(
                                    'alignment',
                                    props.alignments.map((a) => a.alignment),
                                )}
                                <label className="col-form-label">
                                    Walls:{' '}
                                    <InfoTip
                                        id="walls"
                                        text="What the walls between the outside and the inside of the gall are like."
                                    />
                                </label>
                                {makeFormInput(
                                    'walls',
                                    props.walls.map((w) => w.walls),
                                )}
                            </Col>
                            <Col>
                                <label className="col-form-label">
                                    Cells:{' '}
                                    <InfoTip id="locations" text="The number of internal chambers that the gall contains." />
                                </label>
                                {makeFormInput(
                                    'cells',
                                    props.cells.map((c) => c.cells),
                                )}
                                <label className="col-form-label">
                                    Shape: <InfoTip id="locations" text="The overall shape of the gall." />
                                </label>
                                {makeFormInput(
                                    'shape',
                                    props.shapes.map((s) => s.shape),
                                )}
                            </Col>
                            <Col>
                                <label className="col-form-label">
                                    Color: <InfoTip id="locations" text="The outside color of the gall." />
                                </label>
                                {makeFormInput(
                                    'color',
                                    props.colors.map((c) => c.color),
                                )}
                            </Col>
                        </Row>
                    </form>
                </Col>
            </Row>
            {/* Results */}
            {!isHostComplete(hostOrTaxon) && isHost(hostOrTaxon) && (
                <Row>
                    <Col>
                        <Alert variant="warning" className="ml-2 mr-4">
                            This host does not yet have all of the known galls added to the database.
                        </Alert>
                    </Col>
                </Row>
            )}
            <Row className="pl-2 pr-2">
                <Col xs={12} sm={6} md={3}>
                    Showing {filtered.length} of {galls.length} galls:
                </Col>
            </Row>
            <Row className="pl-2 pr-2">
                <Col>
                    <Row>
                        {filtered.map((g) => (
                            <Col key={g.id.toString() + 'col'} xs={6} md={3} className="pb-2">
                                <Card key={g.id} border="secondary">
                                    <Link href={`gall/${g.id}`}>
                                        <a>
                                            <Card.Img
                                                variant="top"
                                                src={defaultImage(g)?.small ? defaultImage(g)?.small : '/images/noimage.jpg'}
                                                alt={`image of ${g.name}`}
                                            />
                                        </a>
                                    </Link>
                                    <Card.Body>
                                        <Card.Title>
                                            <Link href={`gall/${g.id}`}>
                                                <a className="small">{g.name}</a>
                                            </Link>
                                        </Card.Title>
                                        <Card.Text className="small">
                                            {!defaultImage(g) && createSummary(g)}
                                            {session && (
                                                <span className="p-0 pr-1 my-auto">
                                                    <Edit id={g.id} type="gall" />
                                                    {g.datacomplete ? '💯' : '❓'}
                                                </span>
                                            )}
                                        </Card.Text>
                                    </Card.Body>
                                </Card>
                            </Col>
                        ))}
                    </Row>
                </Col>
            </Row>
            <Row className="pl-2 pr-2">
                <Col>
                    {filtered.length == 0 ? (
                        hostOrTaxon == undefined ? (
                            <Alert variant="info" className="small">
                                To begin with select a Host or a Genus to see matching galls. Then you can use the filters to
                                narrow down the list.
                            </Alert>
                        ) : (
                            <Alert variant="info" className="small">
                                There are no galls that match your filter. It’s possible there are no described species that fit
                                this set of traits and your gall is undescribed. However, before giving up, try{' '}
                                <Link href="/guide#troubleshooting">altering your filter choices</Link>.{' '}
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
                        <Alert variant="info" className="small">
                            If none of these results match your gall, you may have found an undescribed species. However, before
                            concluding that your gall is not in the database, try{' '}
                            <Link href="/guide#troubleshooting">altering your filter choices</Link>.{' '}
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
];

// Ideally we would generate this page and serve it statically via getStaticProps and use Incremental Static Regeneration.
// See: https://nextjs.org/docs/basic-features/data-fetching#incremental-static-regeneration
// However, as it stands right now next.js can not support query parameters for static content. This sucks given
// that the query parameters that we have only fiter data on the client side.
// It seems like it might be possible to "solve" this by implementing a convoluted approach using URL paths rather than
// query parameters but I think that would introduce a ton of complexity.
// This will likely end up the most frequently accessed page on the site AND the most resource intensive on the server
// (other than Admin pages which will never have a lot of traffic). My guess is that we will revisiting this issue.
export const getServerSideProps: GetServerSideProps = async (context: { query: ParsedUrlQuery }) => {
    const hosts = await mightFailWithArray<HostSimple>()(allHostsSimple());
    const genera = await mightFailWithArray<TaxonomyEntry>()(allGenera(HostTaxon));
    const sections = await mightFailWithArray<TaxonomyEntry>()(allSections());
    const sectionsAndGenera = [...genera, ...sections].sort((a, b) => a.name.localeCompare(b.name));

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
          }
        : null;

    const locations = await mightFailWithArray<GallLocation>()(getLocations());
    const colors = await mightFailWithArray<ColorApi>()(getColors());
    const seasons = await mightFailWithArray<SeasonApi>()(getSeasons());
    const shapes = await mightFailWithArray<ShapeApi>()(getShapes());
    const textures = await mightFailWithArray<GallTexture>()(getTextures());
    const alignments = await mightFailWithArray<AlignmentApi>()(getAlignments());
    const walls = await mightFailWithArray<WallsApi>()(getWalls());
    const cells = await mightFailWithArray<CellsApi>()(getCells());

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
        },
    };
};

export default IDGall;
