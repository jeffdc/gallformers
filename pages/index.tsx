import { GetServerSideProps } from 'next';
import Head from 'next/head';
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
            <Container className="text-center p-5 ">
                <Row>
                    <Col>
                        <h1>Welcome to Gallformers</h1>
                    </Col>
                </Row>
                <Row>
                    <Col>The place to identify and learn about galls on plants in the US and Canada.</Col>
                </Row>
            </Container>
            <Container>
                <Row>
                    <Col>
                        <Card>
                            <Card.Header>
                                <Link href="/id">
                                    <a style={{ textDecoration: 'none' }}>
                                        <h2>Identify a Gall &rarr;</h2>
                                    </a>
                                </Link>
                            </Card.Header>
                            <Card.Body>Try and get an Identity for a gall by providing known information.</Card.Body>
                        </Card>
                    </Col>
                    <Col>
                        <Card>
                            <Card.Header>
                                <Link href="/explore">
                                    <a style={{ textDecoration: 'none' }}>
                                        <h2>Explore &rarr;</h2>
                                    </a>
                                </Link>
                            </Card.Header>
                            <Card.Body>Explore Galls (including Undescribed species) and Host Plants.</Card.Body>
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
                                        <Card.Title>Help Us Out</Card.Title>
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
                        <Row className="pb-4">
                            <Col>
                                <Card>
                                    <Card.Body>
                                        <Card.Title>Resources</Card.Title>
                                        <ul>
                                            <li>
                                                <Link href="/ref/IDGuide">Our guide to gall identification.</Link>
                                            </li>
                                            <li>
                                                <Link href="/filterguide">Detailed descriptions for our key filters.</Link>
                                            </li>
                                            <li>
                                                <Link href="/glossary">Glossary for plant and insect terms.</Link>
                                            </li>
                                            <li>
                                                To ID galls and other plant symptoms in Europe, visit{' '}
                                                <a href="https://bladmineerders.nl/" target="_blank" rel="noreferrer">
                                                    bladmineerders.nl
                                                </a>
                                            </li>
                                        </ul>
                                    </Card.Body>
                                </Card>
                            </Col>
                        </Row>
                        <Row>
                            <Col>
                                <Card>
                                    <Card.Body>
                                        <Card.Title>Interesting Reading</Card.Title>
                                        <ul>
                                            <li>
                                                If you are new to galls <a href="http://charleyeiseman.com/">Charley Eiseman</a>{' '}
                                                and Noah Charney&apos;s{' '}
                                                <a href="https://bookshop.org/books/tracks-sign-of-insects-other-invertebrates-a-guide-to-north-american-species/9780811736244">
                                                    Tracks & Signs of Insects & Other Invertebrates: A Guide to North American
                                                    Species
                                                </a>{' '}
                                                is a good place to start learning. It covers a lot more than just galls and is an
                                                excellent resource.
                                            </li>
                                            <li>
                                                A long-anticipated update to{' '}
                                                <a href="https://press.princeton.edu/books/paperback/9780691205762/plant-galls-of-the-western-united-states">
                                                    Russo&apos;s guide to galls of the Western US
                                                </a>{' '}
                                                was recently released by Princeton University Press.
                                            </li>
                                            <li>
                                                Some{' '}
                                                <a href="https://www.inaturalist.org/posts/47564-tips-for-gall-hunting">
                                                    advice on finding galls
                                                </a>
                                                .
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
