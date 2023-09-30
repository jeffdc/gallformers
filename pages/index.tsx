import { GetServerSideProps } from 'next';
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
        <Container fluid className="m-0 p-0">
            <Row className="pb-0">
                <Col xs={12} className="text-center p-0 m-0">
                    <h1 className="title pt-3 p-0 m-0">Welcome to Gallformers</h1>
                    <div className="sub-title">The place to identify and learn about galls on plants in the US and Canada.</div>
                </Col>
            </Row>
            <Row className="text-center pb-3"></Row>
            <Row>
                <Col>
                    <Card>
                        <Card.Header>
                            <h2>What the heck is a gall?!</h2>
                        </Card.Header>
                        <Card.Body>
                            Plant galls are abnormal growths of plant tissues, similar to tumors or warts in animals, that have an
                            external cause--such as an insect, mite, nematode, virus, fungus, bacterium, or even another plant
                            species. Growths caused by genetic mutations are not galls. Nor are lerps and other constructions on a
                            plant that do not contain plant tissue. Plant galls are often complex structures that allow the insect
                            or mite that caused the gall to be identified even if that insect or mite is not visible.
                        </Card.Body>
                    </Card>
                </Col>
            </Row>
            <Row className="pb-4 pt-4">
                <Col sm="12" md="6">
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
                                    If you find gallformers.org useful and you are interested in helping us out there are a few
                                    ways you can do so:
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
