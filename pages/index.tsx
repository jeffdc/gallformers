import Link from 'next/link';
import { Card, Col, Container, Row } from 'react-bootstrap';

export default function Home(): JSX.Element {
    return (
        <div>
            <Container className="text-center p-5 ">
                <Row>
                    <Col>
                        <h1>Welcome to Gallformers</h1>
                    </Col>
                </Row>
                <Row>
                    <Col>The place to ID and learn about galls on plants in the US and Canada.</Col>
                </Row>
            </Container>
            <Container>
                <Row>
                    <Col>
                        <Card>
                            <Card.Body>
                                <Link href="/id">
                                    <a>
                                        <h3>ID a Gall &rarr;</h3>
                                        <p>Try and get an ID for a gall by providing known information.</p>
                                    </a>
                                </Link>
                            </Card.Body>
                        </Card>
                    </Col>
                    <Col>
                        <Card>
                            <Card.Body>
                                <Link href="/explore">
                                    <a>
                                        <h3>Explore &rarr;</h3>
                                        <p>Explore Galls (including Undescribed species) and Hosts.</p>
                                    </a>
                                </Link>
                            </Card.Body>
                        </Card>
                    </Col>
                </Row>
                <Row className="pt-4">
                    <Col>
                        <Card>
                            <Card.Body>
                                <Card.Title>Resources</Card.Title>
                                <ul>
                                    <li>
                                        <Link href="/guide">Our guide to gall identification.</Link>
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
                <Row className="pt-4">
                    <Col>
                        <Card>
                            <Card.Body>
                                <Card.Title>Interesting Reading</Card.Title>
                                <ul>
                                    <li>
                                        If you are new to galls <a href="http://charleyeiseman.com/">Charley Eiseman</a> and Noah
                                        Charney&apos;s{' '}
                                        <a href="https://bookshop.org/books/tracks-sign-of-insects-other-invertebrates-a-guide-to-north-american-species/9780811736244">
                                            Tracks & Signs of Insects & Other Invertebrates: A Guide to North American Species
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
            </Container>
        </div>
    );
}
