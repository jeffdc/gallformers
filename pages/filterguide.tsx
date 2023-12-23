import * as O from 'fp-ts/Option';
import { constant } from 'fp-ts/lib/function.js';
import { GetStaticProps } from 'next';
import Head from 'next/head.js';
import Link from 'next/link.js';
import React from 'react';
import { Accordion, Container, ListGroup } from 'react-bootstrap';
import { FilterField } from '../libs/api/apitypes.js';
import { getAlignments, getCells, getForms, getLocations, getShapes, getTextures, getWalls } from '../libs/db/filterfield.js';
import { mightFailWithArray } from '../libs/utils/util.js';

const { Item } = ListGroup;

type Props = {
    alignments: FilterField[];
    cells: FilterField[];
    forms: FilterField[];
    locations: FilterField[];
    shapes: FilterField[];
    textures: FilterField[];
    walls: FilterField[];
};

const filterFieldsToItems = (fields: FilterField[]) =>
    fields
        .sort((a, b) => a.field.localeCompare(b.field))
        .map((a) => (
            <Item key={a.field}>
                <b>{a.field} - </b>
                {O.getOrElse(constant(''))(a.description)}
            </Item>
        ));

const FilterGuide = ({ alignments, cells, forms, locations, shapes, textures, walls }: Props): JSX.Element => {
    return (
        <React.Fragment>
            <Head.default>
                <title>Filter Guide</title>
                <meta name="description" content="A Guide to all of the terms that used on the gallformers ID page." />
            </Head.default>
            <Container fluid className="mt-4 m-2">
                <h1>ID Tool Filter Guide</h1>
                <br />
                <Accordion>
                    <Accordion.Item eventKey="alignment">
                        <Accordion.Header>Alignment</Accordion.Header>
                        <Accordion.Body>
                            <ListGroup>{filterFieldsToItems(alignments)}</ListGroup>
                        </Accordion.Body>
                    </Accordion.Item>
                    <Accordion.Item eventKey="cells">
                        <Accordion.Header>Cells</Accordion.Header>
                        <Accordion.Body>
                            <ListGroup>
                                {filterFieldsToItems(cells)}
                                <Item>
                                    NOTE: If multiple larvae are found in one space, these may be{' '}
                                    <Link.default href="/glossary#inquiline">inquilines</Link.default> rather than gall-inducers.
                                </Item>
                            </ListGroup>
                        </Accordion.Body>
                    </Accordion.Item>
                    <Accordion.Item eventKey="detachable">
                        <Accordion.Header>Detachable</Accordion.Header>
                        <Accordion.Body>
                            <ListGroup>
                                <Item key="yes">
                                    <b>Yes -</b> the gall could be removed from the plant without destroying the tissue it’s
                                    attached to (detachable).
                                </Item>
                                <Item key="no">
                                    <b>No -</b> the gall could only be removed from the plant by destroying the tissue it’s
                                    attached to (integral).
                                </Item>
                                <Item key="note">
                                    NOTE: Galls that have detachable parts but leave some galled tissue behind (more than a scar
                                    or blister), are only detachable in some parts of the season, or may be detachable or not, are
                                    included in both terms.
                                </Item>
                            </ListGroup>
                        </Accordion.Body>
                    </Accordion.Item>
                    <Accordion.Item eventKey="forms">
                        <Accordion.Header>Forms</Accordion.Header>
                        <Accordion.Body>
                            <ListGroup>{filterFieldsToItems(forms)}</ListGroup>
                        </Accordion.Body>
                    </Accordion.Item>
                    <Accordion.Item eventKey="location">
                        <Accordion.Header>Location</Accordion.Header>
                        <Accordion.Body>
                            <ListGroup>{filterFieldsToItems(locations)}</ListGroup>
                        </Accordion.Body>
                    </Accordion.Item>
                    <Accordion.Item eventKey="shape">
                        <Accordion.Header>Shape</Accordion.Header>
                        <Accordion.Body>
                            <ListGroup>{filterFieldsToItems(shapes)}</ListGroup>
                        </Accordion.Body>
                    </Accordion.Item>
                    <Accordion.Item eventKey="texture">
                        <Accordion.Header>Texture</Accordion.Header>
                        <Accordion.Body>
                            <ListGroup>{filterFieldsToItems(textures)}</ListGroup>
                        </Accordion.Body>
                    </Accordion.Item>
                    <Accordion.Item eventKey="walls">
                        <Accordion.Header>Walls</Accordion.Header>
                        <Accordion.Body>
                            <ListGroup>{filterFieldsToItems(walls)}</ListGroup>
                        </Accordion.Body>
                    </Accordion.Item>
                </Accordion>
            </Container>
        </React.Fragment>
    );
};

export const getStaticProps: GetStaticProps = async () => {
    return {
        props: {
            alignments: await mightFailWithArray<FilterField>()(getAlignments()),
            cells: await mightFailWithArray<FilterField>()(getCells()),
            forms: await mightFailWithArray<FilterField>()(getForms()),
            locations: await mightFailWithArray<FilterField>()(getLocations()),
            shapes: await mightFailWithArray<FilterField>()(getShapes()),
            textures: await mightFailWithArray<FilterField>()(getTextures()),
            walls: await mightFailWithArray<FilterField>()(getWalls()),
        },
        revalidate: 1,
    };
};

export default FilterGuide;
