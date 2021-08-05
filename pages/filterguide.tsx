import { GetStaticProps } from 'next';
import Head from 'next/head';
import Link from 'next/link';
import React from 'react';
import { Accordion, Button, Card, Container, ListGroup } from 'react-bootstrap';
import { AlignmentApi, CellsApi, FormApi, GallLocation, GallTexture, ShapeApi, WallsApi } from '../libs/api/apitypes';
import { getAlignments, getCells, getForms, getLocations, getShapes, getTextures, getWalls } from '../libs/db/gall';
import { mightFailWithArray } from '../libs/utils/util';
import * as O from 'fp-ts/Option';
import { constant } from 'fp-ts/lib/function';

const { Item } = ListGroup;

type Props = {
    alignments: AlignmentApi[];
    cells: CellsApi[];
    forms: FormApi[];
    locations: GallLocation[];
    shapes: ShapeApi[];
    textures: GallTexture[];
    walls: WallsApi[];
};

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
                        <ListGroup>
                            {alignments
                                .sort((a, b) => a.alignment.localeCompare(b.alignment))
                                .map((a) => (
                                    <Item key={a.alignment}>
                                        <b>{a.alignment} - </b>
                                        {O.getOrElse(constant(''))(a.description)}
                                    </Item>
                                ))}
                        </ListGroup>
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
                            {cells
                                .sort((a, b) => a.cells.localeCompare(b.cells))
                                .map((a) => (
                                    <Item key={a.cells}>
                                        <b>{a.cells} - </b>
                                        {O.getOrElse(constant(''))(a.description)}
                                    </Item>
                                ))}
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
                            {forms
                                .sort((a, b) => a.form.localeCompare(b.form))
                                .map((a) => (
                                    <Item key={a.form}>
                                        <b>{a.form} - </b>
                                        {O.getOrElse(constant(''))(a.description)}
                                    </Item>
                                ))}
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
                            <ListGroup>
                                {locations
                                    .sort((a, b) => a.loc.localeCompare(b.loc))
                                    .map((a) => (
                                        <Item key={a.loc}>
                                            <b>{a.loc} - </b>
                                            {O.getOrElse(constant(''))(a.description)}
                                        </Item>
                                    ))}
                            </ListGroup>
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
                        <ListGroup>
                            {shapes
                                .sort((a, b) => a.shape.localeCompare(b.shape))
                                .map((a) => (
                                    <Item key={a.shape}>
                                        <b>{a.shape} - </b>
                                        {O.getOrElse(constant(''))(a.description)}
                                    </Item>
                                ))}
                        </ListGroup>
                    </Accordion.Collapse>
                    <Card>
                        <Card.Header>
                            <Accordion.Toggle as={Button} variant="light" eventKey="texture">
                                Texture
                            </Accordion.Toggle>
                        </Card.Header>
                    </Card>
                    <Accordion.Collapse eventKey="texture">
                        <ListGroup>
                            {textures
                                .sort((a, b) => a.tex.localeCompare(b.tex))
                                .map((a) => (
                                    <Item key={a.tex}>
                                        <b>{a.tex} - </b>
                                        {O.getOrElse(constant(''))(a.description)}
                                    </Item>
                                ))}
                        </ListGroup>
                    </Accordion.Collapse>
                    <Card>
                        <Card.Header>
                            <Accordion.Toggle as={Button} variant="light" eventKey="walls">
                                Walls
                            </Accordion.Toggle>
                        </Card.Header>
                    </Card>
                    <Accordion.Collapse eventKey="walls">
                        <ListGroup>
                            {walls
                                .sort((a, b) => a.walls.localeCompare(b.walls))
                                .map((a) => (
                                    <Item key={a.walls}>
                                        <b>{a.walls} - </b>
                                        {O.getOrElse(constant(''))(a.description)}
                                    </Item>
                                ))}
                        </ListGroup>
                    </Accordion.Collapse>
                </Accordion>
            </Container>
        </React.Fragment>
    );
};

export const getStaticProps: GetStaticProps = async () => {
    return {
        props: {
            alignments: await mightFailWithArray<AlignmentApi>()(getAlignments()),
            cells: await mightFailWithArray<CellsApi>()(getCells()),
            forms: await mightFailWithArray<FormApi>()(getForms()),
            locations: await mightFailWithArray<GallLocation>()(getLocations()),
            shapes: await mightFailWithArray<ShapeApi>()(getShapes()),
            textures: await mightFailWithArray<GallTexture>()(getTextures()),
            walls: await mightFailWithArray<WallsApi>()(getWalls()),
        },
        revalidate: 1,
    };
};

export default FilterGuide;
