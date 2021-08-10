import { GetStaticProps } from 'next';
import Head from 'next/head';
import { useRouter } from 'next/router';
import React from 'react';
import { Card, Col, Container, Row, Tab, Tabs } from 'react-bootstrap';
import TreeMenu, { Item, TreeNodeInArray } from 'react-simple-tree-menu';
import 'react-simple-tree-menu/dist/main.css';
import { GallTaxon } from '../libs/api/apitypes';
import { FamilyTaxonomy } from '../libs/api/taxonomy';
import { getFamiliesWithSpecies } from '../libs/db/taxonomy';
import { getStaticPropsWith } from '../libs/pages/nextPageHelpers';
import { hasProp } from '../libs/utils/util';

type Props = {
    gallmakers: TreeNodeInArray[];
    undescribed: TreeNodeInArray[];
    hosts: TreeNodeInArray[];
};

const Explore = ({ gallmakers, undescribed, hosts }: Props): JSX.Element => {
    const router = useRouter();

    const handleClick = (item: Item) => {
        if (hasProp(item, 'url')) {
            router.push(item.url as string);
        }
    };

    return (
        <Container className="pt-2" fluid>
            <Head>
                <title>Explore Galls & Hosts</title>
                <meta name="description" content="Browse all of the galls and hosts that gallformers has in its database." />
            </Head>

            <Row>
                <Col xs={12}>
                    <Card>
                        <Card.Header>
                            <Tabs defaultActiveKey="galls">
                                <Tab eventKey="galls" title="Galls">
                                    <Card.Body>
                                        <Card.Title>Browse Galls - By Family</Card.Title>
                                        <TreeMenu data={gallmakers} onClickItem={handleClick} />
                                    </Card.Body>
                                </Tab>
                                <Tab eventKey="undescribed" title="Undescribed Galls">
                                    <Card.Body>
                                        <Card.Title>Browse Undescibed Galls</Card.Title>
                                        <TreeMenu data={undescribed} onClickItem={handleClick} />
                                    </Card.Body>
                                </Tab>
                                <Tab eventKey="hosts" title="Hosts">
                                    <Card.Body>
                                        <Card.Title>Browse Hosts - By Family</Card.Title>
                                        <TreeMenu data={hosts} onClickItem={handleClick} />
                                    </Card.Body>
                                </Tab>
                            </Tabs>
                        </Card.Header>
                    </Card>
                </Col>
            </Row>
        </Container>
    );
};

// Use static so that this stuff can be built once on the server-side and then cached.
export const getStaticProps: GetStaticProps = async () => {
    return {
        props: {
            gallmakers: toTree(await getStaticPropsWith(getFamiliesWithSpecies(true), 'gall families')),
            undescribed: toTree(await getStaticPropsWith(getFamiliesWithSpecies(true, true), 'undescribed galls')),
            hosts: toTree(await getStaticPropsWith(getFamiliesWithSpecies(false), 'host familes')),
        },
        revalidate: 1,
    };
};

const toTree = (fgs: readonly FamilyTaxonomy[]): TreeNodeInArray[] =>
    fgs.map((f) => ({
        key: f.id.toString(),
        label: `${f.name} - ${f.description}`,
        nodes: f.taxonomytaxonomy
            .sort((a, b) => a.child.name.localeCompare(b.child.name))
            .map((tt) => ({
                key: tt.child.id.toString(),
                label: tt.child.name,
                nodes: tt.child.speciestaxonomy
                    .sort((a, b) => a.species.name.localeCompare(b.species.name))
                    .map((st) => ({
                        key: st.species.id.toString(),
                        label: st.species.name,
                        url: `/${st.species.taxoncode === GallTaxon ? 'gall' : 'host'}/${st.species.id}`,
                    })),
            })),
    }));

export default Explore;
