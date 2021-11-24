import { useSession } from 'next-auth/client';
import Head from 'next/head';
import Link from 'next/link';
import React from 'react';
import { Col, ListGroup, ListGroupItem, Row } from 'react-bootstrap';
import Auth, { superAdmins } from '../../components/auth';

const Admin = (): JSX.Element => {
    const [session] = useSession();

    return (
        <Auth>
            <div className="p-3 m-3">
                <Head>
                    <title>Administration</title>
                </Head>
                <Row>
                    <Col className="font-weight-bold">Things that you can do as an Admin:</Col>
                </Row>
                <Row>
                    <Col>
                        <ListGroup className="pt-3">
                            <ListGroupItem>
                                Create/modify <Link href="./admin/taxonomy">Taxonomy</Link>
                            </ListGroupItem>
                            <ListGroupItem>
                                Create/modify <Link href="./admin/section">Sections</Link>
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
                            <ListGroupItem>
                                Browse <Link href="./admin/browse/galls">galls</Link>,{' '}
                                <Link href="./admin/browse/hosts">hosts</Link>, or{' '}
                                <Link href="./admin/browse/sources">sources</Link>.
                            </ListGroupItem>
                        </ListGroup>
                    </Col>
                </Row>
                {session?.user?.name && superAdmins.includes(session.user.name) && (
                    <>
                        <Row className="mt-2 mb-2 font-weight-bold">
                            <Col>Super Admin Functions</Col>
                        </Row>
                        <Row>
                            <Col>
                                <ListGroup>
                                    <ListGroupItem>
                                        Create/modify <Link href="./admin/filterterms">Filter Terms</Link>
                                    </ListGroupItem>
                                </ListGroup>
                            </Col>
                        </Row>
                    </>
                )}
                <Row className="pt-5">
                    <Col>
                        If you experience any issues with the Adminstration tools (or anything else on the site).{' '}
                        <a href="https://github.com/jeffdc/gallformers/issues" target="_blank" rel="noreferrer">
                            Look to see
                        </a>{' '}
                        if the issue has already been reported. If it has not, then create a new issue on{' '}
                        <a href="https://github.com/jeffdc/gallformers/issues/new" target="_blank" rel="noreferrer">
                            GitHub
                        </a>
                        . If the issue is critical or you are not sure that it is an issue, then reach out on{' '}
                        <a href="https://gallformerdat-m1g8137.slack.com/archives/C01B319JAG6" target="_blank" rel="noreferrer">
                            Slack
                        </a>
                        .
                    </Col>
                </Row>
            </div>
        </Auth>
    );
};

export default Admin;
