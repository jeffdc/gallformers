import { GetStaticProps } from 'next';
import Head from 'next/head';
import Image from 'next/image';
import React from 'react';
import { Accordion, Button, Card, CardDeck, Col, Row } from 'react-bootstrap';
import { getCurrentStats, Stat } from '../libs/db/stats';
import { mightFailWithArray } from '../libs/utils/util';
import GallMeMaybe from '../public/images/gallmemaybe.jpg';

type Props = {
    stats: Stat[];
    genTime: string;
};

const About = ({ stats, genTime }: Props): JSX.Element => {
    const statMap = new Map(stats.map((s) => [s.type, s.count] as [string, number]));
    return (
        <div className="p-5">
            <Head>
                <title>About Gallformers</title>
                <meta name="description" content="About the creators of gallformers and why we built the site." />
            </Head>

            <Row>
                <Col>
                    <h2>About Us</h2>
                </Col>
            </Row>
            <Row>
                <Col>
                    <p>
                        Gallformers is the product of curious amateurs becoming obsessed. If you are here then you too have at
                        least been touched, if not bitten, by the gall bug. It grows in you, but it is not a{' '}
                        <a href="./glossary#parasitism">parasite</a> nor an <a href="./glossary/#inquiline">inquiline</a>.
                    </p>
                    <p>
                        While you are here we hope that we can help you both ID an unknown plant gall as well as to learn about
                        galls. Whether your interests are very casual, you are a burgeoning scientist, or even a full-fledged{' '}
                        <a href="./glossary#cecidiology">cecidiologist</a> we strive to provide useful tools.
                    </p>
                    <p>
                        This site is open source and you can view the all of the code/data and if so inclined even open a pull
                        request on <a href="https://github.com/jeffdc/gallformers">GitHub</a>.
                    </p>
                </Col>
            </Row>
            <Row>
                <Col>
                    <h4>Contacting Us</h4>
                    <p>
                        You can contact us at <a href="mailto:gallformers@gmail.com">gallformers@gmail.com</a> or{' '}
                        <a href="https://twitter.com/gallformers" target="_blank" rel="noreferrer">
                            @gallformers
                        </a>{' '}
                        on Twitter.
                    </p>
                </Col>
            </Row>
            <Row>
                <Col className="pb-3">
                    <h4>Who We Are</h4>
                    <CardDeck>
                        <Card>
                            <Card.Body className="small">
                                <Card.Title>Adam Kranz</Card.Title>
                                <Card.Text>
                                    Adam is an independent ecologist focused on gall inducing organisms in North America. He
                                    co-founded Gallformers.org as a community resource to help naturalists identify gall
                                    observations and to collect information on undescribed galls. His primary focus is on adding
                                    literature and information to the Gallformers database.
                                </Card.Text>
                            </Card.Body>
                            <Card.Footer>
                                <Card.Link href="https://www.inaturalist.org/people/megachile" target="_blank" rel="noreferrer">
                                    iNaturalist
                                </Card.Link>
                                <Card.Link href="https://twitter.com/adam_kranz" target="_blank" rel="noreferrer">
                                    Twitter
                                </Card.Link>
                            </Card.Footer>
                        </Card>
                        <Card>
                            <Card.Body className="small">
                                <Card.Title>Jeff Clark</Card.Title>
                                <Card.Text>
                                    Jeff is a Software Engineer who stumbled upon galls and became obsessed. So much so that he
                                    co-founded this site, wrote all the code for this site, and is responsible for keeping it
                                    going, fixing it, and implementing new features (and is currently the sole financial
                                    supporter). If the site is broken, it is most likely his fault.
                                </Card.Text>
                            </Card.Body>
                            <Card.Footer>
                                <Card.Link href="https://www.inaturalist.org/people/jeffdc" target="_blank" rel="noreferrer">
                                    iNaturalist
                                </Card.Link>
                                <Card.Link href="https://twitter.com/jeffc666" target="_blank" rel="noreferrer">
                                    Twitter
                                </Card.Link>
                            </Card.Footer>
                        </Card>
                        <Card>
                            <Card.Body className="small">
                                <Card.Title>Yann Kemper</Card.Title>
                                <Card.Text>
                                    Yann is a 17 year old student from Cincinnati, Ohio. For the past three years he has been an
                                    active contributor on iNaturalist, developing a recent interest in galls in the process.
                                </Card.Text>
                            </Card.Body>
                            <Card.Footer>
                                <Card.Link href="https://www.inaturalist.org/people/kemper" target="_blank" rel="noreferrer">
                                    iNaturalist
                                </Card.Link>
                            </Card.Footer>
                        </Card>
                    </CardDeck>
                </Col>
            </Row>
            <Row className="pb-2">
                <Col>
                    Besides the folks profiled above, others help out by contributing code, data, and feedback to help us improve
                    the site.
                </Col>
            </Row>
            <Row>
                <Col>
                    <h4>Current Site Stats:</h4>
                    As of <span className="font-italic">{genTime}</span> there are:
                    <ul>
                        <li>
                            {statMap.get('galls')} gallformers across {statMap.get('gall-family')} families and{' '}
                            {statMap.get('gall-genera')} genera, of which {statMap.get('undescribed')} are undescribed
                        </li>
                        <li>
                            {statMap.get('hosts')} hosts across {statMap.get('host-family')} families and{' '}
                            {statMap.get('host-genera')} genera
                        </li>
                        <li>{statMap.get('sources')} sources</li>
                    </ul>
                </Col>
            </Row>
            <Row>
                <Col>
                    <h4>Citing Gallformers</h4>
                    <p>
                        All of our original content is released under a{' '}
                        <a href="https://creativecommons.org/licenses/by/4.0/" target="_blank" rel="noreferrer">
                            CC-BY
                        </a>{' '}
                        license.
                    </p>
                    <p>
                        Gallformers would be impossible without the many contributions from the scientific literature as well as
                        the many individuals that have allowed usage of their wonderful photos. We have made every effort to
                        verify and document the license for all content that we use. If you find anything that you think is
                        incorrect please contact us: <a href="mailto:gallformers@gmail.com">Email</a> or{' '}
                        <a href="https://twitter.com/gallformers" target="_blank" rel="noreferrer">
                            Twitter
                        </a>
                    </p>
                    <p>
                        If you are interested in using information on Gallformers in your own research please do. All we ask is
                        that you cite Gallformers and that if you are using any content that is not original to Gallformers that
                        you please cite the original source. When applicable, please cite the specific ID Notes containing the
                        claim being cited.
                    </p>
                    <h5>Citation</h5>
                    <span>
                        <div className="citation">
                            “Gallformers Contributors.” Www.gallformers.org, www.gallformers.org. Accessed [date]‌
                        </div>
                        <div className="citation">
                            “Gallformers Contributors.” &ldquo;[<i>Species name</i>]&rdquo; Notes on ID and Taxonomy,
                            Www.gallformers.org/[url to specific species], www.gallformers.org. Accessed [date]‌
                        </div>
                    </span>
                </Col>
            </Row>
            <Row className="mt-1 pt-1">
                <Col className="mt-5 pt-5 text-right">
                    <pre className="font-weight-light small text-muted">Build: {process.env.BUILD_ID}</pre>
                </Col>
            </Row>
            <Row>
                <Col>
                    <Accordion>
                        <Card.Header>
                            <Accordion.Toggle as={Button} variant="link" eventKey="0">
                                Dare You Click?
                            </Accordion.Toggle>
                        </Card.Header>
                        <Accordion.Collapse eventKey="0">
                            <Card.Body className="d-flex justify-content-center">
                                <Image src={GallMeMaybe} alt="Gall Me Maybe" width="300" height="532" layout="fixed" />
                            </Card.Body>
                        </Accordion.Collapse>
                    </Accordion>
                </Col>
            </Row>
        </div>
    );
};

export const getStaticProps: GetStaticProps = async () => {
    return {
        props: {
            stats: await mightFailWithArray<Stat>()(getCurrentStats()),
            genTime: new Date().toUTCString(),
        },
        revalidate: 5 * 60, // every 5 minutes
    };
};

export default About;
