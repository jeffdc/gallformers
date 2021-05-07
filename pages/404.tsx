import Link from 'next/link';
import React from 'react';
import { Container, Jumbotron, Row, Col } from 'react-bootstrap';

export default function FourOhFour(): JSX.Element {
    return (
        <Container className="pt-2" fluid>
            <Row>
                <Col xs={12}>
                    <Jumbotron>
                        <Row className="p-1 justify-content-md-center">
                            <h1>404</h1>
                        </Row>
                        <Row className="p-1 justify-content-md-center">
                            <h2>This Page Was Not Found</h2>
                        </Row>
                        <Row className="p-1 justify-content-md-center">
                            <p>Notably this is also not a gall, though it sure does look like one.</p>
                        </Row>
                        <Row className="p-1 justify-content-md-center">
                            <a href="https://www.inaturalist.org/observations/58767231" target="_blank" rel="noreferrer">
                                <img src="/images/scale.jpg" />
                            </a>
                        </Row>
                        <Row className="p-3 justify-content-md-center">
                            <p>
                                <Link href="/">
                                    <a>Go back home</a>
                                </Link>
                            </p>
                        </Row>
                    </Jumbotron>
                </Col>
            </Row>
        </Container>
    );
}
