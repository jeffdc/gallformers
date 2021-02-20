import { GetStaticProps } from 'next';
import Head from 'next/head';
import Link from 'next/link';
import React from 'react';
import { Accordion, Button, Card, ListGroup, Tab, Tabs } from 'react-bootstrap';
import { FamilyGeneraSpecies } from '../libs/api/apitypes';
import { getFamiliesWithSpecies } from '../libs/db/family';
import { getStaticPropsWith } from '../libs/pages/nextPageHelpers';

type Props = {
    gallmakers: FamilyGeneraSpecies[];
    hosts: FamilyGeneraSpecies[];
};

const lister = (f: FamilyGeneraSpecies, gall: boolean) => {
    const path = gall ? 'gall' : 'host';
    return f.taxonomytaxonomy
        .sort((a, b) => a.child.name.localeCompare(b.child.name))
        .map((s) => (
            <ListGroup.Item key={s.child.id}>
                {s.child.name}
                {' - '}
                {s.child.speciestaxonomy
                    .sort((a, b) => a.species.name.localeCompare(b.species.name))
                    .map((st) => (
                        <Link key={st.species.id} href={`/${path}/${st.species.id}`}>
                            <a className="pr-2">{st.species.name}</a>
                        </Link>
                    ))}
            </ListGroup.Item>
        ));
};

const renderList = (data: FamilyGeneraSpecies[], gall: boolean) => {
    return data.map((f) => (
        <Card key={f.id}>
            <Card.Header>
                <Accordion.Toggle as={Button} variant="light" eventKey={f.id.toString()}>
                    <i>{f.name}</i> - {f.description}
                </Accordion.Toggle>
            </Card.Header>
            <Accordion.Collapse eventKey={f.id.toString()}>
                <Card.Body>
                    <ListGroup>{lister(f, gall)}</ListGroup>
                </Card.Body>
            </Accordion.Collapse>
        </Card>
    ));
};

const Explore = ({ gallmakers, hosts }: Props): JSX.Element => {
    return (
        <>
            <Head>
                <title>Explore Galls</title>
            </Head>

            <Card>
                <Card.Header>
                    <Tabs defaultActiveKey="galls">
                        <Tab eventKey="galls" title="Galls">
                            <Card.Body>
                                <Card.Title>Browse Galls</Card.Title>
                                <Card.Text>By Family</Card.Text>
                                <Accordion>{renderList(gallmakers, true)}</Accordion>
                            </Card.Body>
                        </Tab>
                        <Tab eventKey="hosts" title="Hosts">
                            <Card.Body>
                                <Card.Title>Browse Hosts</Card.Title>
                                <Card.Text>By Family</Card.Text>
                                <Accordion>{renderList(hosts, false)}</Accordion>
                            </Card.Body>
                        </Tab>
                    </Tabs>
                </Card.Header>
            </Card>
        </>
    );
};

// Use static so that this stuff can be built once on the server-side and then cached.
export const getStaticProps: GetStaticProps = async () => {
    return {
        props: {
            gallmakers: await getStaticPropsWith(getFamiliesWithSpecies(true), 'gall families'),
            hosts: await getStaticPropsWith(getFamiliesWithSpecies(false), 'host familes'),
        },
        revalidate: 1,
    };
};

export default Explore;
