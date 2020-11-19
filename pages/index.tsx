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
                    <Col>The place to ID and learn about galls on plants.</Col>
                </Row>
            </Container>
            <Container>
                <Row>
                    <Col>
                        <Card>
                            <Card.Body>
                                <Link href="id">
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
                                <Link href="explore">
                                    <a>
                                        <h3>Explore &rarr;</h3>
                                        <p>Explore and investigate Galls, including locating primary sources.</p>
                                    </a>
                                </Link>
                            </Card.Body>
                        </Card>
                    </Col>
                </Row>
            </Container>
        </div>
    );
}
