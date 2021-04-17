import { yupResolver } from '@hookform/resolvers/yup';
import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetServerSideProps } from 'next';
import Head from 'next/head';
import Link from 'next/link';
import { useRouter } from 'next/router';
import { ParsedUrlQuery } from 'querystring';
import React, { useEffect, useState } from 'react';
import { Button, Col, ListGroup, Row } from 'react-bootstrap';
import { useForm } from 'react-hook-form';
import * as yup from 'yup';
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
    ShapeApi,
    WallsApi,
} from '../libs/api/apitypes';
import { SECTION, TaxonomyEntry, TaxonomyEntryNoParent } from '../libs/api/taxonomy';
import { alignments, cells, colors, locations, shapes, textures, walls } from '../libs/db/gall';
import { allHostsSimple } from '../libs/db/host';
import { allGenera, allSections } from '../libs/db/taxonomy';
import { defaultImage, truncateOptionString } from '../libs/pages/renderhelpers';
import { checkGall } from '../libs/utils/gallsearch';
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
};

const invalidArraySelection = (arr: unknown[]) => {
    return arr?.length === 0;
};

const isTaxonomy = (o: unknown): o is TaxonomyEntryNoParent => hasProp(o, 'type');
const isHost = (o: unknown): o is HostSimple => hasProp(o, 'aliases');

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
              shape: q.shape.join(','),
              textures: q.textures.join(','),
              walls: q.walls.join(','),
          }
        : null),
});

const IDGall = (props: Props): JSX.Element => {
    const [galls, setGalls] = useState(new Array<GallApi>());
    const [filtered, setFiltered] = useState(new Array<GallApi>());
    const [hostOrTaxon, setHostOrTaxon] = useState(props?.hostOrTaxon);
    const [query, setQuery] = useState(props.query);

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

    // this is the faceted filter form
    const { control: filterControl, reset: resetFilter } = useForm<FilterFormFields>();

    const resetForm = () => {
        setHostOrTaxon(undefined);
        setQuery(null);
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
                    console.log(`${field} changed`);
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
        <>
            <Head>
                <title>ID Galls</title>
            </Head>

            <form className="fixed-left mt-2 ml-4 mr-2 form-group">
                <Row>
                    <Col>
                        First select either the host species or the genus/section for a host if you are unsure of the species,
                        then press Search. You can then filter the found galls using the boxes on the left.
                    </Col>
                </Row>
                <Row>
                    <Col>
                        <label className="col-form-label">Host:</label>
                        <Typeahead
                            name="host"
                            control={control}
                            selected={hostOrTaxon && isHost(hostOrTaxon) ? [hostOrTaxon] : []}
                            onChange={(h) => {
                                setHostOrTaxon(h[0]);
                                // if (query) {
                                //     setQuery({
                                //         ...query,
                                //         detachable: query.detachable ? query.detachable : [],
                                //         key: h[0] as HostSimple,
                                //     });
                                // } else {
                                //     setQuery(EMPTYSEARCHQUERY);
                                // }
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
                    <Col xs={1} className="align-self-end">
                        - or -
                    </Col>
                    <Col>
                        <label className="col-form-label">Genus (Section):</label>
                        <Typeahead
                            name="genus"
                            control={control}
                            selected={hostOrTaxon && isTaxonomy(hostOrTaxon) ? [hostOrTaxon] : []}
                            onChange={(g) => {
                                setHostOrTaxon(g[0]);
                                // setQuery({
                                //     ...query,
                                //     key: g[0],
                                // });
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
            <hr />
            <Row>
                <Col xs={3}>
                    <form className="fixed-left ml-4 form-group">
                        <Row>
                            <Col>
                                <label className="col-form-label">
                                    Location(s):
                                    <InfoTip id="locations" text="Where on the host the gall is found." />
                                </label>
                            </Col>
                            <Col xs={5} className="mr-0 pr-0">
                                <Button variant="outline-primary" size="sm" onClick={resetForm}>
                                    Reset Form
                                </Button>
                            </Col>
                        </Row>
                        {makeFormInput(
                            'locations',
                            props.locations.map((l) => l.loc),
                            true,
                        )}
                        <hr />
                        <p className="font-italic small">
                            Start with Host/Genus & Location. Many galls will not have associated information for all of the below
                            properties.
                        </p>
                        <label className="col-form-label">
                            Texture(s):
                            <InfoTip
                                id="textures"
                                text="The look and feel of the gall. If you are unsure what any of the terms mean check the glossary (? icon on top right)."
                            />
                        </label>
                        {makeFormInput(
                            'textures',
                            props.textures.map((t) => t.tex),
                            true,
                        )}
                        <label className="col-form-label">
                            Detachable: <InfoTip id="detachable" text="Can the gall be removed from the host without cutting?" />
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
                                    detachable: selected,
                                });
                            }}
                            placeholder="Detachable"
                            options={Detachables}
                            labelKey={'value'}
                            disabled={disableFilter()}
                            clearButton={true}
                        />
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
                            <InfoTip id="walls" text="What the walls between the outside and the inside of the gall are like." />
                        </label>
                        {makeFormInput(
                            'walls',
                            props.walls.map((w) => w.walls),
                        )}
                        <label className="col-form-label">
                            Cells: <InfoTip id="locations" text="The number of internal chambers that the gall contains." />
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
                        <label className="col-form-label">
                            Color: <InfoTip id="locations" text="The outside color of the gall." />
                        </label>
                        {makeFormInput(
                            'color',
                            props.colors.map((c) => c.color),
                        )}
                    </form>
                </Col>
                <Col className="mt-2 form-group mr-4">
                    <Row className="m-2">
                        Showing {filtered.length} of {galls.length} galls.
                    </Row>
                    {/* <Row className='border m-2'><p className='text-right'>Pager TODO</p></Row> */}
                    <Row className="m-2">
                        <ListGroup>
                            {filtered.length == 0 ? (
                                hostOrTaxon == undefined ? (
                                    <h4 className="font-weight-lighter">
                                        To begin with select a Host or a Genus to see matching galls. Then you can use the filters
                                        on the left to narrow down the list.
                                    </h4>
                                ) : (
                                    <h4 className="font-weight-lighter">There are no galls that match your filter.</h4>
                                )
                            ) : (
                                filtered.map((g) => (
                                    <ListGroup.Item key={g.id}>
                                        <Row key={g.id}>
                                            <Col xs={3} className="">
                                                <img src={defaultImage(g)?.small} width="125px" className="img-responsive" />
                                            </Col>
                                            <Col className="pl-0 pull-right">
                                                <Link href={`gall/${g.id}`}>
                                                    <a>{g.name}</a>
                                                </Link>
                                                - {truncateOptionString(g.description)}
                                            </Col>
                                        </Row>
                                    </ListGroup.Item>
                                ))
                            )}
                        </ListGroup>
                    </Row>
                </Col>
            </Row>
        </>
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
];

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
              shape: pipe(query['shape'], O.fold(constant([]), split)),
              textures: pipe(query['textures'], O.fold(constant([]), split)),
              walls: pipe(query['walls'], O.fold(constant([]), split)),
          }
        : null;

    return {
        props: {
            hostOrTaxon: hostOrTaxon,
            query: searchQuery,
            hosts: hosts,
            sectionsAndGenera: sectionsAndGenera,
            locations: await mightFailWithArray<GallLocation>()(locations()),
            colors: await mightFailWithArray<ColorApi>()(colors()),
            shapes: await mightFailWithArray<ShapeApi>()(shapes()),
            textures: await mightFailWithArray<GallTexture>()(textures()),
            alignments: await mightFailWithArray<AlignmentApi>()(alignments()),
            walls: await mightFailWithArray<WallsApi>()(walls()),
            cells: await mightFailWithArray<CellsApi>()(cells()),
        },
    };
};

export default IDGall;
