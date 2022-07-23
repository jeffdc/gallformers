import { GetServerSideProps } from 'next';
import Head from 'next/head';
import Image from 'next/image';
import Link from 'next/link';
import React from 'react';
import { Card, Col, Container, Row } from 'react-bootstrap';
import { RandomGall } from '../libs/api/apitypes';
import { randomGall } from '../libs/db/gall';
import { getStaticPropsWith } from '../libs/pages/nextPageHelpers';

type Props = {
    randomGall: RandomGall;
};

function Home({ randomGall }: Props): JSX.Element {
    return (
        <>
            <Head>
                <meta name="description" content="The place to ID and learn about galls on plants in the US and Canada." />
            </Head>
            <Container className="">
                <Row className="d-flex pb-0">
                    <Col xs={3} className="text-end p-0 m-0">
                        <Image src="/images/cynipid_L.svg" width="100" height="100" />
                    </Col>
                    <Col xs={6} className="text-center p-0 m-0">
                        <h1>Welcome to Gallformers</h1>
                        <div>The place to identify and learn about galls on plants in the US and Canada.</div>
                    </Col>
                    <Col xs={3} className="text-start p-0 m-0">
                        <Image src="/images/cynipid_R.svg" width="100" height="100" />
                    </Col>
                </Row>
                <Row className="text-center pb-3"></Row>
                <Row>
                    <Col>
                        <Card>
                            <Card.Header>
                                <h2>Things To Do</h2>
                            </Card.Header>
                            <Card.Body>
                                <Row>
                                    <Col>
                                        <Link href="/id">
                                            <a style={{ textDecoration: 'none' }}>
                                                <h3>Identify a Gall &rarr;</h3>
                                            </a>
                                        </Link>
                                    </Col>
                                    <Col>
                                        <Link href="/explore">
                                            <a style={{ textDecoration: 'none' }}>
                                                <h3>Explore &rarr;</h3>
                                            </a>
                                        </Link>
                                    </Col>
                                </Row>
                                <Row>
                                    <Col>
                                        <Link href="/resources">
                                            <a style={{ textDecoration: 'none' }}>
                                                <h3>Resources &rarr;</h3>
                                            </a>
                                        </Link>
                                    </Col>
                                    <Col>
                                        <Link href="/glossary">
                                            <a style={{ textDecoration: 'none' }}>
                                                <h3>Glossary &rarr;</h3>
                                            </a>
                                        </Link>
                                    </Col>
                                </Row>
                            </Card.Body>
                        </Card>
                    </Col>
                    <Col>
                        <Card>
                            <Card.Header>
                                <h2>What the heck is a gall?!</h2>
                            </Card.Header>
                            <Card.Body>
                                Plant galls are abnormal growths of plant tissues, similar to tumors or warts in animals, that
                                have an external cause--such as an insect, mite, nematode, virus, fungus, bacterium, or even
                                another plant species. Growths caused by genetic mutations are not galls. Nor are lerps and other
                                constructions on a plant that do not contain plant tissue. Plant galls are often complex
                                structures that allow the insect or mite that caused the gall to be identified even if that insect
                                or mite is not visible.
                            </Card.Body>
                        </Card>
                    </Col>
                </Row>
                <Row className="pb-4 pt-4">
                    <Col md="12" lg="6">
                        <Card>
                            <Link href={`/gall/${randomGall.id}`}>
                                <a>
                                    <Card.Img variant="top" src={randomGall.imagePath} width="300" />
                                </a>
                            </Link>{' '}
                            <Card.Body>
                                Here is a random gall from our database. This one is{' '}
                                {randomGall.undescribed ? 'an undescribed species' : ''} called{' '}
                                <Link href={`/gall/${randomGall.id}`}>
                                    <a>
                                        <i>{randomGall.name}</i>
                                    </a>
                                </Link>{' '}
                                and the photo was taken by{' '}
                                <a href={randomGall.sourceLink} target="_blank" rel="noreferrer">
                                    {randomGall.creator}
                                </a>{' '}
                                ©{' '}
                                {randomGall.licenseLink ? (
                                    <a href={randomGall.licenseLink} target="_blank" rel="noreferrer">
                                        {randomGall.license}
                                    </a>
                                ) : (
                                    randomGall.license
                                )}
                            </Card.Body>
                        </Card>
                    </Col>
                    <Col>
                        <Row className="pb-4">
                            <Col>
                                <Card>
                                    <Card.Body>
                                        <Card.Title>
                                            <h2>Help Us Out</h2>
                                        </Card.Title>
                                        If you find gallformers.org useful and you are interested in helping us out there are a
                                        few ways you can do so:
                                        <ul>
                                            <li>
                                                <Link href="https://www.patreon.com/gallformers">
                                                    Help cover operational costs via donations to our Patreon
                                                </Link>
                                            </li>
                                            <li>
                                                <Link href="/about#administrators">
                                                    Help add and maintain our data as an Administrator
                                                </Link>
                                            </li>
                                            <li>
                                                <Link href="https://github.com/jeffdc/gallformers">
                                                    Help fix bugs and add new features
                                                </Link>
                                            </li>
                                        </ul>
                                    </Card.Body>
                                </Card>
                            </Col>
                        </Row>
                    </Col>
                </Row>
            </Container>
        </>
    );
}

export const getServerSideProps: GetServerSideProps = async () => {
    const gall = await getStaticPropsWith<RandomGall>(randomGall, 'gall');

    return {
        props: {
            randomGall: gall[0],
        },
    };
};

export default Home;
