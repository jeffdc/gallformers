import { Container } from 'next/app';
import React from 'react';
import { Col, Row } from 'react-bootstrap';

export default function About(): JSX.Element {
    return (
        <div className="p-5">
            <Container>
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
                            While you are here we hope that we can help you both ID an unknown plant gall as well as to learn
                            about galls. Whether your interests are very casual, you are a burgeoning scientist, or even a
                            full-fledged <a href="./glossary#cecidiology">cecidiologist</a> we strive to provide useful tools.
                        </p>
                        <p>
                            This site is open source and you can view the all of the code/data and if so inclined even open a pull
                            request on <a href="https://github.com/jeffdc/gallformers">GitHub</a>.
                        </p>
                    </Col>
                </Row>
            </Container>
        </div>
    );
}
