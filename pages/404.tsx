import Link from 'next/link';
import React from 'react';
import { Jumbotron, Row } from 'react-bootstrap';

export default function FourOhFour(): JSX.Element {
    return (
        <Jumbotron className="m-1">
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
    );
}
