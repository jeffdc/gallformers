import { yupResolver } from '@hookform/resolvers/yup';
import { GetServerSideProps } from 'next';
import Head from 'next/head';
import Link from 'next/link';
import React, { useState } from 'react';
import { Col, ListGroup, Row } from 'react-bootstrap';
import { useForm } from 'react-hook-form';
import * as yup from 'yup';
import InfoTip from '../components/infotip';
import Typeahead from '../components/Typeahead';
import {
    AlignmentApi,
    CellsApi,
    ColorApi,
    DetachableDetachable,
    DetachableIntegral,
    DetachableNone,
    emptySearchQuery,
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
import { capitalizeFirstLetter, mightFailWithArray } from '../libs/utils/util';

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
    detachable: string;
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

const IDGall = (props: Props): JSX.Element => {
    const [galls, setGalls] = useState(new Array<GallApi>());
    const [filtered, setFiltered] = useState(new Array<GallApi>());
    const [query, setQuery] = useState(emptySearchQuery());
    const [host, setHost] = useState<Array<HostSimple>>([]);
    const [genus, setGenus] = useState<Array<TaxonomyEntryNoParent>>([]);

    const disableFilter = (): boolean => {
        return host.length < 1 && genus.length < 1;
    };

    // this is the search form on sepcies or genus
    const {
        control,
        // setValue,
        handleSubmit,
        formState: { errors },
    } = useForm<SearchFormFields>({
        mode: 'onBlur',
        resolver: yupResolver(Schema),
    });

    // this is the faceted filter form
    const { control: filterControl, reset: filterReset } = useForm<FilterFormFields>();

    const updateQuery = (f: keyof SearchQuery, v: string | string[]): SearchQuery => {
        const qq: SearchQuery = { ...query };
        if (f === 'host') {
            qq.host = Array.isArray(v) ? v[0] : v;
        } else if (f !== 'detachable') {
            qq[f] = Array.isArray(v) ? v : [v];
        } else {
            // detachable
            qq[f] = v[0] === 'yes' ? DetachableDetachable : v[0] === 'no' ? DetachableIntegral : DetachableNone;
        }
        return qq;
    };

    // this is the handler for changing either species or genus, it makes a DB round trip.
    const onSubmit = async () => {
        try {
            // make sure to clear all of the filters since we are getting a new set of galls
            filterReset();
            let query = '';
            if (host && host.length) {
                query = encodeURI(`?host=${host[0].name}`);
            } else if (genus && genus.length > 0) {
                if (genus[0].type === SECTION) {
                    query = `?section=${genus[0].name}`;
                } else {
                    query = `?genus=${genus[0].name}`;
                }
            }

            const res = await fetch(`../api/search${query}`, {
                method: 'GET',
            });

            if (res.status === 200) {
                const g = (await res.json()) as GallApi[];
                if (!g || !Array.isArray(g)) {
                    throw new Error('Received an invalid search result.');
                }
                setGalls(g.sort((a, b) => a.name.localeCompare(b.name)));
                setFiltered(g);
            } else {
                throw new Error(await res.text());
            }
        } catch (e) {
            console.error(e);
        }
    };

    // this is the handler for changing any other field, all work is done locally
    const doSearch = async (field: keyof FilterFormFields, value: string | string[]) => {
        const newq = updateQuery(field, value);
        const f = galls.filter((g) => checkGall(g, newq));
        setFiltered(f);
        setQuery(newq);
    };

    const makeFormInput = (field: keyof FilterFormFields, opts: string[], multiple = false) => {
        return (
            <Typeahead
                name={field}
                control={filterControl}
                onChange={(selected) => {
                    doSearch(field, selected);
                }}
                onKeyDownT={(e) => {
                    if (e.key === 'Enter') {
                        doSearch(field, e.currentTarget.value);
                    }
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

            <form onSubmit={handleSubmit(onSubmit)} className="fixed-left mt-2 ml-4 mr-2 form-group">
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
                            selected={host ? host : []}
                            onChange={(h) => {
                                setGenus([]);
                                setHost(h);
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
                            selected={genus ? genus : []}
                            onChange={(h) => {
                                setHost([]);
                                setGenus(h);
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
                <Row>
                    <Col className="pt-2">
                        <input type="submit" value="Search" className=" btn btn-secondary" />
                    </Col>
                </Row>
            </form>
            <hr />
            <Row>
                <Col xs={3}>
                    <form className="fixed-left ml-4 form-group">
                        <label className="col-form-label">
                            Location(s):
                            <InfoTip id="locations" text="Where on the host the gall is found." />
                        </label>
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
                        {makeFormInput('detachable', ['yes', 'no'])}
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
                                query == undefined || query.host == undefined ? (
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
                                            <Col xs={2} className="">
                                                <img
                                                    src={defaultImage(g)?.small}
                                                    width="75px"
                                                    height="75px"
                                                    className="img-responsive"
                                                />
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

export const getServerSideProps: GetServerSideProps = async () => {
    const genera = await mightFailWithArray<TaxonomyEntry>()(allGenera(HostTaxon));
    const sections = await mightFailWithArray<TaxonomyEntry>()(allSections());
    const sectionsAndGenera = [...genera, ...sections].sort((a, b) => a.name.localeCompare(b.name));

    return {
        props: {
            hosts: await mightFailWithArray<HostSimple>()(allHostsSimple()),
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
