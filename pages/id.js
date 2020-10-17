import fetch from 'isomorphic-unfetch';
import React, { useState } from 'react';
import { Typeahead } from 'react-bootstrap-typeahead';
import { Container, Button, Form, Col } from 'react-bootstrap';
import {useRouter} from "next/router";

const Id = ({ hosts, hostNameMap, locations, textures, colors, alignments, shapes, cells, walls }) => {
    const router = useRouter(); 
    const [host, setHost] = useState("");
    const [location, setLocation] = useState("");
    const [detachable, setDetachable] = useState("");
    const [texture, setTexture] = useState("");
    const [alignment, setAlignment] = useState("");
    const [wall, setWall] = useState("");
    const [cell, setCell] = useState("");
    const [color, setColor] = useState("");
    const [shape, setShape] = useState("");

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
                walls: wall,
                cells: cell,
                color: color,
                shape: shape                
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
                            multiple
                            labelKey="t"
                            onChange={setTexture}
                            options={textures}
                            placeholder="What is the texture of the gall?"
                        />
                    </Form.Group>   
                    <Form.Group as={Col} controlId="formAlignment">
                        <Form.Label>Alignment</Form.Label>
                        <Typeahead
                            id="alignment"
                            labelKey="a"
                            onChange={setAlignment}
                            options={alignments}
                            placeholder="What is the alignment of the gall?"
                        />
                    </Form.Group>
                    <Form.Group as={Col} controlId="formWalls">
                        <Form.Label>Walls</Form.Label>
                        <Typeahead
                            id="walls"
                            labelKey="w"
                            onChange={setWall}
                            options={walls}
                            placeholder="What are the walls of the gall like?"
                        />
                    </Form.Group>
                </Form.Row>
                <Form.Row>
                    <Form.Group as={Col} controlId="formCells">
                        <Form.Label>Cells</Form.Label>
                        <Typeahead
                            id="cells"
                            labelKey="c"
                            onChange={setCell}
                            options={cells}
                            placeholder="How many cells in the gall?"
                        />
                    </Form.Group>   
                    <Form.Group as={Col} controlId="formColor">
                        <Form.Label>Color</Form.Label>
                        <Typeahead
                            id="color"
                            labelKey="cl"
                            onChange={setColor}
                            options={colors}
                            placeholder="What color is the gall?"
                        />
                    </Form.Group>
                    <Form.Group as={Col} controlId="formShape">
                        <Form.Label>Shape</Form.Label>
                        <Typeahead
                            id="shape"
                            labelKey="p"
                            onChange={setShape}
                            options={shapes}
                            placeholder="What shape is the gall?"
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
        [h.name, h.commonnames]
    ).filter(h => h).sort();
    let hostNameMap = h.reduce ( (m, h) => (m[h.commonname] = h.name, m), {} );
    
    return { hosts, hostNameMap };
}

// helper that fetches the static lookup data at url and then returns the the results mapped using the function f
async function fetchLookups(url, f) {
    const response = await fetch(url);
    const j = await response.json();

    return j.map(f)
}

// Use static so that this stuff can be built once on the server-side and then cached.
export async function getStaticProps() {
    let { hosts, hostNameMap } = await fetchHosts();
    return { props: {
           hosts: hosts,
           hostNameMap: hostNameMap,
           locations: await fetchLookups('http://localhost:3000/api/gall/location', (l => l.loc)),
           colors: await fetchLookups('http://localhost:3000/api/gall/color', (c => c.color)),
           shapes: await fetchLookups('http://localhost:3000/api/gall/shape', (s => s.shape)),
           textures: await fetchLookups('http://localhost:3000/api/gall/texture', (t => t.texture)),
           alignments: await fetchLookups('http://localhost:3000/api/gall/alignment', (a => a.alignment)),
           walls: await fetchLookups('http://localhost:3000/api/gall/walls', (w => w.walls)),
           cells: await fetchLookups('http://localhost:3000/api/gall/cells', (c => c.cells))
        }
    }
}

export default Id;