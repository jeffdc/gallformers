import fetch from 'isomorphic-unfetch';
import React, { useState } from 'react';
import { Typeahead } from 'react-bootstrap-typeahead';
import { Container, Row, Col, FormControl, Button, Form } from 'react-bootstrap';

const Id = ({ hosts }) => {
    let selected;

    return (    
    <div style={{
        marginBottom: '5%'
    }}>
        <Container>
            <Row className="p-3">
                <Col>
                    To begin, we need to know what the Host species is for the gall. Begin typing in the name of the host (either its binomial scientific name or the common name) in the box below and press 'Search':
                </Col>
            </Row>
            <Row>
                <Col>
                    <Form>
                        <Form.Label>Host Species</Form.Label>
                        <Typeahead
                            id="host-species"
                            labelKey="name"
                            onChange={(s) => this.setState({ selected: s })}
                            options={hosts}
                            placeholder="Choose a host species"
                            selected={selected}
                        />
                    </Form>
                </Col>
            </Row>
        </Container>
    </div>
  )
};

export async function getStaticProps() {
    const response = await fetch('http://localhost:3000/api/host');
    const hosts = await response.json();

    const all = hosts.flatMap ( h =>
        [h.name, h.commonname]
    ).sort();

    return { props: {
           hosts: all,
        }
    }
}

export default Id;