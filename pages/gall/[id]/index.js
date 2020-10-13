import React from 'react';
import { Col, Container, ListGroup, Media, Row} from 'react-bootstrap';

const Gall = ({ gall }) => {
    return (    
    <div style={{
        marginBottom: '5%'
    }}>
        <Media>
            <img
                width={170}
                height={128}
                className="mr-3"
                src=""
                alt={gall.name + '\nPhoto pending'}
            />
            <Media.Body>
                <Container className='p-3 border'>
                    <Row>
                        <Col><h1>{gall.name}</h1></Col>
                        <Col className='text-right font-italic'>Family: {gall.family}</Col>
                    </Row>
                    <Row>
                        <Col className='lead p-3'>{gall.description}</Col>
                    </Row>
                    <Row>
                        <Col>
                            Hosts: {gall.hosts.map(h => h.name).join(', ')}
                        </Col>
                    </Row>
                    <Row>
                        <Col>Detachable: {gall.detachable == 1 ? 'yes' : 'no'}</Col>
                        <Col>Texture: {gall.texture}</Col>
                        <Col>Alignment: {gall.alignment}</Col>
                    </Row>
                    <Row>
                        <Col>Location: {gall.loc}</Col>
                        <Col>Walls: {gall.walls}</Col>
                        <Col>Abdundance: {gall.abundance}</Col>
                    </Row>
                    <Row>
                        <Col>Further Information: 
                            <ListGroup>
                                {gall.sources.map((source) =>
                                    <ListGroup.Item key={source.id} action href={source.link}>{source.citation}</ListGroup.Item>
                                )}
                            </ListGroup>
                        </Col>
                    </Row>
                </Container>
            </Media.Body>
        </Media>
    </div>
  )
};


async function fetchGall(id) {
    const url = 'http://localhost:3000/api/gall/' + id;
    const resGall = await fetch(url);
    const gall = await resGall.json();

    const resHosts = await fetch(url + '/hosts');
    gall.hosts = await resHosts.json();

    const resSources = await fetch(url + '/sources');
    gall.sources = await resSources.json();

    return gall
}

// Use static so that this stuff can be built once on the server-side and then cached.
export async function getStaticProps(context) {
    return { props: {
           gall: await fetchGall(context.params.id),
        }
    }
}

export async function getStaticPaths() {
    const res = await fetch('http://localhost:3000/api/gall');
    const galls = await res.json();

    const paths = galls.map((gall) => ({
        params: { id: gall.species_id.toString() },
    }));

    return { paths, fallback: false }
}

export default Gall;