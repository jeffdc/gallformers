import { family, species } from '@prisma/client';
import { GetStaticPaths, GetStaticProps } from 'next';
import Link from 'next/link';
import React from 'react';
import { Col, Container, ListGroup, Media, Row } from 'react-bootstrap';
import { allFamilyIds, familyById, speciesByFamily } from '../../../libs/db/family';

type Props = {
    family: family;
    species: species[];
};

function makeSpeciesLink(s: species) {
    const speciesType = s.taxoncode === 'gall' ? 'gall' : 'host';
    return (
        <Link key={s.id} href={`/${speciesType}/${s.id}`}>
            <a>{s.name} </a>
        </Link>
    );
}

const Family = ({ family, species }: Props): JSX.Element => {
    return (
        <div
            style={{
                marginBottom: '5%',
                marginRight: '5%',
            }}
        >
            <Media>
                <Media.Body>
                    <Container className="p-3 border">
                        <Row>
                            <Col>
                                <h1>{family.name}</h1>
                            </Col>
                        </Row>
                        <Row>
                            <Col className="lead p-3">{family.description}</Col>
                        </Row>
                        <Row>
                            <ListGroup>
                                {species.map((s) => (
                                    <ListGroup.Item key={s.id}>{makeSpeciesLink(s)}</ListGroup.Item>
                                ))}
                            </ListGroup>
                        </Row>
                    </Container>
                </Media.Body>
            </Media>
        </div>
    );
};

// Use static so that this stuff can be built once on the server-side and then cached.
export const getStaticProps: GetStaticProps = async (context) => {
    if (context === undefined || context.params === undefined || context.params.id === undefined) {
        throw new Error(`Family id can not be undefined.`);
    } else if (Array.isArray(context.params.id)) {
        throw new Error(`Expected single id but got an array of ids ${context.params.id}.`);
    }

    const familyId = parseInt(context.params.id);

    return {
        props: {
            family: await familyById(familyId),
            species: await speciesByFamily(familyId),
        },
        revalidate: 1,
    };
};

export const getStaticPaths: GetStaticPaths = async () => {
    const familyIds = await allFamilyIds();

    const paths = familyIds.map((f) => ({
        params: { id: f },
    }));

    return { paths, fallback: false };
};

export default Family;
