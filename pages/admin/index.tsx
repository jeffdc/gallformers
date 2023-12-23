import { useSession } from 'next-auth/react';
import Head from 'next/head.js';
import Link from 'next/link.js';
import { Col, ListGroup, ListGroupItem, Row } from 'react-bootstrap';
import Auth, { superAdmins } from '../../components/auth.js';

const Admin = (): JSX.Element => {
    const { data: session } = useSession();

    return (
        <Auth>
            <div className="p-3 m-3">
                <Head.default>
                    <title>Administration</title>
                </Head.default>
                <Row>
                    <Col className="font-weight-bold">Things that you can do as an Admin:</Col>
                </Row>
                <Row>
                    <Col>
                        <ListGroup className="pt-3">
                            <ListGroupItem>
                                Create/modify <Link.default href="./admin/taxonomy">Taxonomy</Link.default>
                            </ListGroupItem>
                            <ListGroupItem>
                                Create/modify <Link.default href="./admin/section">Sections</Link.default>
                            </ListGroupItem>
                            <ListGroupItem>
                                Create/modify <Link.default href="./admin/host">Hosts</Link.default>
                            </ListGroupItem>
                            <ListGroupItem>
                                Create/modify <Link.default href="./admin/gall">Galls</Link.default>
                            </ListGroupItem>
                            <ListGroupItem>
                                Add/Edit <Link.default href="./admin/images">Images</Link.default>
                            </ListGroupItem>
                            <ListGroupItem>
                                Create <Link.default href="./admin/gallhost">Gall-Host Mappings</Link.default>
                            </ListGroupItem>{' '}
                            <ListGroupItem>
                                Create/modify <Link.default href="./admin/source">Sources</Link.default>
                            </ListGroupItem>
                            <ListGroupItem>
                                Create <Link.default href="./admin/speciessource">Species-Source Mappings</Link.default>
                            </ListGroupItem>
                            <ListGroupItem>
                                Create/modify <Link.default href="./admin/glossary">Glossary Entries</Link.default>
                            </ListGroupItem>
                            <ListGroupItem>
                                Browse <Link.default href="./admin/browse/galls">galls</Link.default>,{' '}
                                <Link.default href="./admin/browse/hosts">hosts</Link.default>, or{' '}
                                <Link.default href="./admin/browse/sources">sources</Link.default>.
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
                                        Create/modify <Link.default href="./admin/filterterms">Filter Terms</Link.default>
                                    </ListGroupItem>
                                    <ListGroupItem>
                                        Create/modify <Link.default href="./admin/place">Places</Link.default>
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
