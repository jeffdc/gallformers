import { constant } from 'fp-ts/lib/function';
import * as O from 'fp-ts/Option';
import { GetStaticProps } from 'next';
import Head from 'next/head';
import Link from 'next/link';
import React from 'react';
import { Accordion, Button, Card, Container, ListGroup } from 'react-bootstrap';
import { FilterField } from '../libs/api/apitypes';
import { getAlignments, getCells, getForms, getLocations, getShapes, getTextures, getWalls } from '../libs/db/filterfield';
import { mightFailWithArray } from '../libs/utils/util';

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
            <Head>
                <title>Filter Guide</title>
            </Head>
            <Container fluid className="mt-4 m-2">
                <h1>ID Tool Filter Guide</h1>
                <br />
                <Accordion>
                    <Card>
                        <Card.Header>
                            <Accordion.Toggle as={Button} variant="light" eventKey="alignment">
                                Alignment
                            </Accordion.Toggle>
                        </Card.Header>
                    </Card>
                    <Accordion.Collapse eventKey="alignment">
                        <ListGroup>{filterFieldsToItems(alignments)}</ListGroup>
                    </Accordion.Collapse>
                    <Card>
                        <Card.Header>
                            <Accordion.Toggle as={Button} variant="light" eventKey="cells">
                                Cells
                            </Accordion.Toggle>
                        </Card.Header>
                    </Card>
                    <Accordion.Collapse eventKey="cells">
                        <ListGroup>
                            {filterFieldsToItems(cells)}
                            <Item>
                                NOTE: If multiple larvae are found in one space, these may be{' '}
                                <Link href="/glossary#inquiline">inquilines</Link> rather than gall-inducers.
                            </Item>
                        </ListGroup>
                    </Accordion.Collapse>
                    <Card>
                        <Card.Header>
                            <Accordion.Toggle as={Button} variant="light" eventKey="detachable">
                                Detachable
                            </Accordion.Toggle>
                        </Card.Header>
                    </Card>
                    <Accordion.Collapse eventKey="detachable">
                        <ListGroup>
                            <Item key="yes">
                                <b>Yes -</b> the gall could be removed from the plant without destroying the tissue it’s attached
                                to (detachable).
                            </Item>
                            <Item key="no">
                                <b>No -</b> the gall could only be removed from the plant by destroying the tissue it’s attached
                                to (integral).
                            </Item>
                            <Item key="note">
                                NOTE: Galls that have detachable parts but leave some galled tissue behind (more than a scar or
                                blister), are only detachable in some parts of the season, or may be detachable or not, are
                                included in both terms.
                            </Item>
                        </ListGroup>
                    </Accordion.Collapse>
                    <Card>
                        <Card.Header>
                            <Accordion.Toggle as={Button} variant="light" eventKey="forms">
                                Forms
                            </Accordion.Toggle>
                        </Card.Header>
                    </Card>
                    <Accordion.Collapse eventKey="forms">
                        <ListGroup>
                            {filterFieldsToItems(forms)}
                            {/* <Item key="gall">
                                <b>Gall -</b> a novel element of a plant caused by an organism living within the plant.
                            </Item> */}
                        </ListGroup>
                    </Accordion.Collapse>
                    <Card>
                        <Card.Header>
                            <Accordion.Toggle as={Button} variant="light" eventKey="location">
                                Location
                            </Accordion.Toggle>
                        </Card.Header>
                        <Accordion.Collapse eventKey="location">
                            <ListGroup>{filterFieldsToItems(locations)}</ListGroup>
                        </Accordion.Collapse>
                    </Card>
                    <Card>
                        <Card.Header>
                            <Accordion.Toggle as={Button} variant="light" eventKey="shape">
                                Shape
                            </Accordion.Toggle>
                        </Card.Header>
                    </Card>
                    <Accordion.Collapse eventKey="shape">
                        <ListGroup>{filterFieldsToItems(shapes)}</ListGroup>
                    </Accordion.Collapse>
                    <Card>
                        <Card.Header>
                            <Accordion.Toggle as={Button} variant="light" eventKey="texture">
                                Texture
                            </Accordion.Toggle>
                        </Card.Header>
                    </Card>
                    <Accordion.Collapse eventKey="texture">
                        <ListGroup>{filterFieldsToItems(textures)}</ListGroup>
                    </Accordion.Collapse>
                    <Card>
                        <Card.Header>
                            <Accordion.Toggle as={Button} variant="light" eventKey="walls">
                                Walls
                            </Accordion.Toggle>
                        </Card.Header>
                    </Card>
                    <Accordion.Collapse eventKey="walls">
                        <ListGroup>{filterFieldsToItems(walls)}</ListGroup>
                    </Accordion.Collapse>
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
