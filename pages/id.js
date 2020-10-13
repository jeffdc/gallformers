import fetch from 'isomorphic-unfetch';
import React, { useState } from 'react';
import { Typeahead } from 'react-bootstrap-typeahead';
import { Container, Button, Form, Col } from 'react-bootstrap';
import {useRouter} from "next/router";

const Id = ({ hosts, hostNameMap, locations }) => {
    const router = useRouter(); 
    const [host, setHost] = useState("");
    const [location, setLocation] = useState("");
    const [detachable, setDetachable] = useState(false);
    const [texture, setTexture] = useState("");
    const [alignment, setAlignment] = useState("");
    const [walls, setWalls] = useState("");

    const handleSubmit = e => {
        e.preventDefault();
        router.push({
            pathname: '/search',
            query: {
                host: hostNameMap[host] ? hostNameMap[host] : host,
                location: location,
                detachable: detachable,
                texture: texture,
                alignment: alignment,
                walls: walls,                
            },
        })
    }

    return (    
    <div style={{
        marginBottom: '5%'
    }}>
        <Container>
            To help ID a gall we need to gather some info. Fill in as much as you can.
            <Form onSubmit={handleSubmit}> 
                <Form.Row>
                    <Form.Group as={Col} controlId="formHost">
                        <Form.Label>Host Species</Form.Label>
                        <Typeahead
                            id="host-species"
                            labelKey="name"
                            onChange={setHost}
                            options={hosts}
                            placeholder="What is the host species?"
                        />
                    </Form.Group>
                    <Form.Group as={Col} controlId="formLocation">
                        <Form.Label>Location</Form.Label>
                        <Typeahead
                            id="location"
                            multiple
                            labelKey="loc"
                            onChange={setLocation}
                            options={locations}
                            placeholder="Where is the gall located?"
                        />
                    </Form.Group>
                    <Form.Group as={Col} controlId="formDetachable">
                        <Form.Check 
                            id="detachable" 
                            label="Detachable?" 
                            onClick={setDetachable}
                        />
                    </Form.Group>
                </Form.Row>
                <Form.Row>
                    <Form.Group as={Col} controlId="formTexture">
                        <Form.Label>Texture</Form.Label>
                        <Typeahead
                            id="texture"
                            labelKey="t"
                            onChange={setTexture}
                            options={[ {t:"hairless"}, {t:"hairy"}]}
                            placeholder="What is the texture of the gall?"
                        />
                    </Form.Group>   
                    <Form.Group as={Col} controlId="formAlignment">
                        <Form.Label>Alignment</Form.Label>
                        <Typeahead
                            id="alignment"
                            labelKey="a"
                            onChange={setAlignment}
                            options={[ {a:"erect"}, {a:"droopping"}]}
                            placeholder="What is the alignment of the gall?"
                        />
                    </Form.Group>
                    <Form.Group as={Col} controlId="formWalls">
                        <Form.Label>Walls</Form.Label>
                        <Typeahead
                            id="walls"
                            labelKey="w"
                            onChange={setWalls}
                            options={[ {w:"thin"}, {w:"thick"}, {w:"broken"}]}
                            placeholder="What are the walls of the gall like?"
                        />
                    </Form.Group>
                </Form.Row>
                <Button variant="primary" type="submit">
                    Find Galls
                </Button>
            </Form>
        </Container>
    </div>
  )
};


async function fetchHosts() {
    const response = await fetch('http://localhost:3000/api/host');
    const h = await response.json();

    let hosts = h.flatMap ( h =>
        [h.name, h.commonNames]
    ).filter(h => h).sort();
    let hostNameMap = h.reduce ( (m, h) => (m[h.commonname] = h.name, m), {} );
    
    return { hosts, hostNameMap };
}

async function fetchGallLocations() {
    const response = await fetch('http://localhost:3000/api/galllocation');
    const j = await response.json();

    return j.map(l => l.loc)
}

// Use static so that this stuff can be built once on the server-side and then cached.
export async function getStaticProps() {
    let { hosts, hostNameMap } = await fetchHosts();
    return { props: {
           hosts: hosts,
           hostNameMap: hostNameMap,
           locations: await fetchGallLocations()
        }
    }
}

export default Id;