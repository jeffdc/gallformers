import { yupResolver } from '@hookform/resolvers/yup';
import { alignment, cells as dbcells, color, location, shape, texture, walls as dbwalls } from '@prisma/client';
import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetServerSideProps } from 'next';
import Link from 'next/link';
import React, { useState } from 'react';
import { Col, ListGroup, Row } from 'react-bootstrap';
import { Control, useForm } from 'react-hook-form';
import * as yup from 'yup';
import ControlledTypeahead from '../components/controlledtypeahead';
import { emptySearchQuery, GallApi, SearchQuery } from '../libs/api/apitypes';
import { alignments, cells, colors, locations, shapes, textures, walls } from '../libs/db/gall';
import { allHostGenera, allHostNames } from '../libs/db/host';
import { checkGall } from '../libs/utils/gallsearch';
import { mightFail, truncateAtWord } from '../libs/utils/util';

type SearchFormHostField = {
    host: string;
    genus?: never;
};

type SearchFormGenusField = {
    host?: never;
    genus: string;
};

type SearchFormFields = SearchFormHostField | SearchFormGenusField;

// keep TS happy since the allowable field values are bound when we set the defaultValues above in the useForm() call.
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

const Schema = yup.object().shape(
    {
        host: yup.string().when('genus', {
            is: '',
            then: yup.string().required('You must provide a search,'),
            otherwise: yup.string(),
        }),
        genus: yup.string().when('host', {
            is: '',
            then: yup.string().required('You must provide a search,'),
            otherwise: yup.string(),
        }),
    },
    [['host', 'genus']],
);

type Props = {
    hosts: string[];
    genera: string[];
    locations: location[];
    colors: color[];
    shapes: shape[];
    textures: texture[];
    alignments: alignment[];
    walls: dbwalls[];
    cells: dbcells[];
};

const Search2 = (props: Props): JSX.Element => {
    if (
        !props.hosts ||
        !props.genera ||
        !props.locations ||
        !props.colors ||
        !props.shapes ||
        !props.textures ||
        !props.alignments ||
        !props.walls ||
        !props.cells
    ) {
        throw new Error('Invalid props passed to Search.');
    }

    const [galls, setGalls] = useState(new Array<GallApi>());
    const [filtered, setFiltered] = useState(new Array<GallApi>());
    const [query, setQuery] = useState(emptySearchQuery());

    const disableFilter = (): boolean => {
        const host = getValues(['host']);
        const genus = getValues(['genus']);
        return (!host || !host.host) && (!genus || !genus.genus);
    };

    // this is the search form on sepcies or genus
    const { control, getValues, setValue, handleSubmit, errors } = useForm<SearchFormFields>({
        mode: 'onBlur',
        resolver: yupResolver(Schema),
    });

    // this is the faceted filter form
    const { control: filterControl, reset: filterReset } = useForm<FilterFormFields>();

    const updateQuery = (f: keyof SearchQuery, v: string | string[]): SearchQuery => {
        const qq: SearchQuery = { ...query };
        if (f === 'host') {
            qq.host = v as string;
        } else if (f === 'locations' || f === 'textures') {
            qq[f] = v as string[];
        } else {
            const s = v[0];
            qq[f] = s.length >= 1 ? O.of(s) : O.none;
        }
        return qq;
    };

    // this is the handler for changing either species or genus, it makes a DB round trip.
    const onSubmit = async ({ host, genus }: SearchFormFields) => {
        try {
            // make sure to clear all of the filters since we are getting a new set of galls
            filterReset();
            const query = encodeURI(host ? `?host=${host}` : `?genus=${genus}`);
            const res = await fetch(`../api/search${query}`, {
                method: 'GET',
            });

            if (res.status === 200) {
                const g = (await res.json()) as GallApi[];
                if (!g || !Array.isArray(g)) {
                    throw new Error('Received an invalid search result.');
                }
                setGalls(g);
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
        console.log(
            `search: ${JSON.stringify(newq)} got: ${JSON.stringify(f.map((f) => f.name))} from ${JSON.stringify(
                galls.map((g) => g.name),
            )}`,
        );
        setFiltered(f);
        setQuery(newq);
    };

    const makeFormInput = (field: keyof FilterFormFields, opts: string[], multiple = false) => {
        return (
            <ControlledTypeahead
                control={filterControl as Control<Record<string, unknown>>}
                name={field}
                onChange={(selected) => {
                    doSearch(field, selected);
                }}
                onKeyDown={(e) => {
                    if (e.key === 'Enter') {
                        doSearch(field, e.currentTarget.value);
                    }
                }}
                placeholder={field.charAt(0).toUpperCase() + field.slice(1)}
                options={opts}
                disabled={disableFilter()}
                clearButton={true}
                multiple={multiple}
            />
        );
    };

    return (
        <>
            <form onSubmit={handleSubmit(onSubmit)} className="fixed-left mt-2 ml-4 mr-2 form-group">
                <Row>
                    <Col>
                        <label className="col-form-label">Host:</label>
                        <ControlledTypeahead
                            control={control}
                            name="host"
                            onBlur={() => {
                                setValue('genus', '');
                            }}
                            placeholder="Host"
                            clearButton
                            options={props.hosts}
                        />
                    </Col>
                    <Col xs={1} className="align-self-center">
                        - or -
                    </Col>
                    <Col>
                        <label className="col-form-label">Genus:</label>
                        <ControlledTypeahead
                            control={control}
                            name="genus"
                            onBlur={() => {
                                setValue('host', '');
                            }}
                            placeholder="Genus"
                            clearButton
                            options={props.genera}
                        />
                    </Col>
                </Row>
                <Row>
                    <Col>
                        {errors.host && (
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
            <Row>
                <Col xs={3}>
                    <form className="fixed-left ml-4 form-group">
                        <label className="col-form-label">Location(s):</label>
                        {makeFormInput(
                            'locations',
                            props.locations.map((l) => l.location),
                            true,
                        )}
                        <label className="col-form-label">Texture(s):</label>
                        {makeFormInput(
                            'textures',
                            props.textures.map((t) => t.texture),
                            true,
                        )}
                        <label className="col-form-label">Detachable:</label>
                        {makeFormInput('detachable', ['yes', 'no', 'unsure'])}
                        <label className="col-form-label">Aligment:</label>
                        {makeFormInput(
                            'alignment',
                            props.alignments.map((a) => a.alignment),
                        )}
                        <label className="col-form-label">Walls:</label>
                        {makeFormInput(
                            'walls',
                            props.walls.map((w) => w.walls),
                        )}
                        <label className="col-form-label">Cells:</label>
                        {makeFormInput(
                            'cells',
                            props.cells.map((c) => c.cells),
                        )}
                        <label className="col-form-label">Shape:</label>
                        {makeFormInput(
                            'shape',
                            props.shapes.map((s) => s.shape),
                        )}
                        <label className="col-form-label">Color:</label>
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
                                                    src="images/gall.jpg"
                                                    width="75px"
                                                    height="75px"
                                                    className="img-responsive"
                                                />
                                            </Col>
                                            <Col className="pl-0 pull-right">
                                                <Link href={`gall/${g.id}`}>
                                                    <a>{g.name}</a>
                                                </Link>
                                                - {gallDescription(g.description)}
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

const gallDescription = (description: O.Option<string>): string => {
    // eslint-disable-next-line prettier/prettier
    return pipe(
        description,
        O.map(truncateAtWord(40)),
        O.getOrElse(constant('')),
    )    
};

export const getServerSideProps: GetServerSideProps = async () => {
    // get all of the data for the typeahead boxes
    return {
        props: {
            hosts: await mightFail(allHostNames()),
            genera: await mightFail(allHostGenera()),
            locations: await mightFail(locations()),
            colors: await mightFail(colors()),
            shapes: await mightFail(shapes()),
            textures: await mightFail(textures()),
            alignments: await mightFail(alignments()),
            walls: await mightFail(walls()),
            cells: await mightFail(cells()),
        },
    };
};

export default Search2;
