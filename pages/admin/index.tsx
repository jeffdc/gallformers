import Head from 'next/head';
import Link from 'next/link';
import React from 'react';
import { Col, ListGroup, ListGroupItem, Row } from 'react-bootstrap';
import Auth from '../../components/auth';

const Admin = (): JSX.Element => {
    return (
        <Auth>
            <div className="p-3 m-3">
                <Head>
                    <title>Administration</title>
                </Head>
                <Row>
                    <Col>Things that you can do as an Admin:</Col>
                </Row>
                <Row>
                    <Col>
                        <ListGroup className="pt-3">
                            <ListGroupItem>
                                Create/modify <Link href="./admin/family">Families</Link>
                            </ListGroupItem>
                            <ListGroupItem>
                                Create/modify <Link href="./admin/host">Hosts</Link>
                            </ListGroupItem>
                            <ListGroupItem>
                                Create/modify <Link href="./admin/gall">Galls</Link>
                            </ListGroupItem>
                            <ListGroupItem>
                                Add/Edit <Link href="./admin/images">Images</Link>
                            </ListGroupItem>
                            <ListGroupItem>
                                Create <Link href="./admin/gallhost">Gall-Host Mappings</Link>
                            </ListGroupItem>{' '}
                            <ListGroupItem>
                                Create/modify <Link href="./admin/source">Sources</Link>
                            </ListGroupItem>
                            <ListGroupItem>
                                Create <Link href="./admin/speciessource">Species-Source Mappings</Link>
                            </ListGroupItem>
                            <ListGroupItem>
                                Create/modify <Link href="./admin/glossary">Glossary Entries</Link>
                            </ListGroupItem>
                        </ListGroup>
                    </Col>
                </Row>
                <Row className="pt-5">
                    <Col>
                        This stuff hopefully all works. I have tested a bunch but I am sure that there are still bugs. If you see
                        wonkiness then message me (Jeff) on Slack and I will look into it.
                    </Col>
                </Row>
            </div>
        </Auth>
    );
};

export default Admin;
