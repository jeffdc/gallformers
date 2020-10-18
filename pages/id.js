import fetch from 'isomorphic-unfetch';
import React from 'react';
import { Container,Form, Button, Col } from 'react-bootstrap';
import {useRouter} from "next/router";
import { Formik } from 'formik';
import * as yup from 'yup';
import InfoTip from './components/infotip';
import SearchFormField from './components/searchformfield';

const schema = yup.object({
    hostName: yup.string().required('You must provide a host name.'),
    location: yup.string(),
    detachable: yup.string(),
    texture: yup.string(),
    alignment: yup.string(),
    walls: yup.string(),
    cells: yup.string(),
    color: yup.string(),
    shape: yup.string(),
});

const Id = ({ hosts, hostNameMap, locations, textures, colors, alignments, shapes, cells, walls }) => {
    const router = useRouter();

    return (    
    <div style={{
        marginBottom: '5%'
    }}>
        <Formik
            initialValues={{ hostName:"", location:"", detachable:"", texture:"", alignment:"", walls:"", cells:"", color:"", shape:""}}
            validationSchema={schema}
            onSubmit={ (values, {setSubmitting, resetForm}) => {
                setSubmitting(true);
                console.log("SUBMIT YO");
                router.push({
                    pathname: '/search',
                    query: {
                        host: hostNameMap[values.hostName] ? hostNameMap[values.hostName] : values.hostName,
                        location: values.location,
                        // we display 'unsure' to the user, but it is easier to treat it as an empty string from here on out
                        detachable: values.detachable === 'unsure' ? '' : values.detachable,
                        texture: values.texture,
                        alignment: values.alignment,
                        walls: values.walls,
                        cells: values.cells,
                        color: values.color,
                        shape: values.shape                
                    },
                });
                // resetForm();
                setSubmitting(false);
            }}
        >
            {({
                handleSubmit,
                isSubmitting,
                touched,
                errors,
            }) => (
                <Container className="pt-4">
                    <p><i>
                        To help ID a gall we need to gather some info. Fill in as much as you can but at a minimum we need to know the host species.
                    </i></p>
                    <Form noValidate onSubmit={handleSubmit}>
                        <Form.Row>
                            <Form.Group as={Col} controlId="formHost">
                                <Form.Label>Host Species (required)</Form.Label>
                                <InfoTip text="The host plant that the gall is found on." />
                                <SearchFormField 
                                    name="hostName"
                                    touched={touched}
                                    errors={errors}
                                    options={hosts}
                                    placeholder="What is the host species?"
                                />                        
                            </Form.Group>
                            <Form.Group as={Col} controlId="formLocation">
                                <Form.Label>Location</Form.Label>
                                <InfoTip text="Where on the host plant is the gall found? You can select multiple properties." />
                                <SearchFormField 
                                    name="location"
                                    touched={touched}
                                    errors={errors}
                                    options={locations}
                                    placeholder="Where is the gall located?"
                                />
                            </Form.Group>
                            <Form.Group as={Col} controlId="detachable">
                                <Form.Label>Detachable</Form.Label>
                                <InfoTip text="Can the gall be removed from the host plant or is it integral?" />
                                <SearchFormField 
                                    name="detachable"
                                    touched={touched}
                                    errors={errors}
                                    options={['unsure', 'yes', 'no']}
                                    placeholder="Is the gall detachable?"
                                />
                            </Form.Group>
                        </Form.Row>
                        <Form.Row>
                            <Form.Group as={Col} controlId="formTexture">
                                <Form.Label>Texture</Form.Label>
                                <InfoTip text="The overall look and feel of the gall." />
                                <SearchFormField 
                                    name="texture"
                                    touched={touched}
                                    errors={errors}
                                    options={textures}
                                    placeholder="What is the texture of the gall?"
                                />
                            </Form.Group>   
                            <Form.Group as={Col} controlId="formAlignment">
                                <Form.Label>Alignment</Form.Label>
                                <InfoTip text="Is the gall straight up and down, leaning, etc.?" />
                                <SearchFormField 
                                    name="alignment"
                                    touched={touched}
                                    errors={errors}
                                    options={alignments}
                                    placeholder="What is the alignment of the gall?"
                                />
                            </Form.Group>
                            <Form.Group as={Col} controlId="formWalls">
                                <Form.Label>Walls</Form.Label>
                                <InfoTip text="If the gall is cut open what are the walls like?" />
                                <SearchFormField 
                                    name="walls"
                                    touched={touched}
                                    errors={errors}
                                    options={walls}
                                    placeholder="What are the walls of the gall like?"
                               />
                            </Form.Group>
                        </Form.Row>
                        <Form.Row>
                            <Form.Group as={Col} controlId="formCells">
                                <Form.Label>Cells</Form.Label>
                                <InfoTip text="How many cells (where the larvae are) are there in the gall?" />
                                <SearchFormField 
                                    name="texture"
                                    touched={touched}
                                    errors={errors}
                                    options={cells}
                                    placeholder="How many cells in the gall?"
                                />
                            </Form.Group>   
                            <Form.Group as={Col} controlId="formColor">
                                <Form.Label>Color</Form.Label>
                                <InfoTip text="What color is the gall?" />
                                <SearchFormField 
                                    name="texture"
                                    touched={touched}
                                    errors={errors}
                                    options={colors}
                                    placeholder="What color is the gall?"
                                />
                            </Form.Group>
                            <Form.Group as={Col} controlId="formShape">
                                <Form.Label>Shape</Form.Label>
                                <InfoTip text="What is the shape of the gall?" />
                                <SearchFormField 
                                    name="texture"
                                    touched={touched}
                                    errors={errors}
                                    options={shapes}
                                    placeholder="What shape is the gall?"
                                />
                            </Form.Group>
                        </Form.Row>
                        <Button variant="primary" type="submit" disabled={isSubmitting}>
                            Find Galls
                        </Button>
                    </Form>
                </Container> 
            )}
        </Formik>
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