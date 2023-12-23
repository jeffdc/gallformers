import Image from 'next/image.js';
import Link from 'next/link';
import React from 'react';
import { Container, Row, Col } from 'react-bootstrap';

export default function FourOhFour(): JSX.Element {
    return (
        <Container className="pt-2" fluid>
            <Row>
                <Col className="p-5 justify-content-center d-flex">
                    <div className="p-5 text-black bg-light rounded-3">
                        <Row className="p-1 text-center">
                            <h1>404</h1>
                        </Row>
                        <Row className="p-1 text-center">
                            <h2>This Page Was Not Found</h2>
                        </Row>
                        <Row className="p-1 text-center">
                            <p>Notably this is also not a gall, though it sure does look like one.</p>
                        </Row>
                        <Row className="p-1 justify-content-md-center">
                            <a href="https://www.inaturalist.org/observations/58767231" target="_blank" rel="noreferrer">
                                <Image src="../public/images/scale.jpg" alt="A scale insect not a gall." />
                            </a>
                        </Row>
                        <Row className="p-3">
                            <p>
                                <Link href="/">Go back home</Link>
                            </p>
                        </Row>
                    </div>
                </Col>
            </Row>
        </Container>
    );
}
