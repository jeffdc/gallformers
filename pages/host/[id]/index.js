import Link from 'next/link';
import React from 'react';
import { Col, Container, Media, Row} from 'react-bootstrap';
import { getGallsByHost, getHost, getHosts } from '../../../database';

function gallAsLink(g) {
    return ( <Link key={g.species_id} href={"/gall/[id]"} as={`/gall/${g.species_id}`}><a>{g.name} </a></Link> )
}

const Host = ({ host }) => {
    return (    
    <div style={{
        marginBottom: '5%',
        marginRight: '5%'
    }}>
        <Media>
            <img
                width={170}
                height={128}
                className="mr-3"
                src=""
                alt={host.name}
            />
            <Media.Body>
                <Container className='p-3 border'>
                    <Row>
                        <Col><h1>{host.name}</h1></Col>
                        <Col className='text-right font-italic'>Family: {host.family}</Col>
                    </Row>
                    <Row>
                        <Col className='lead p-3'>{host.description}</Col>
                    </Row>
                    <Row>
                        <Col>
                            Galls: { host.galls.map(gallAsLink) }
                        </Col>
                    </Row>
                    <Row>
                        <Col>Abdundance: {host.abundance}</Col>
                    </Row>
                </Container>
            </Media.Body>
        </Media>
    </div>
  )
};


async function fetchHost(id) {
    const host = await getHost(id);
    host.galls = await getGallsByHost(id);

    return host
}

// Use static so that this stuff can be built once on the server-side and then cached.
export async function getStaticProps(context) {
    return { props: {
           host: await fetchHost(context.params.id),
        }
    }
}

export async function getStaticPaths() {
    const hosts = await getHosts();

    const paths = hosts.map((host) => ({
        params: { id: host.species_id.toString() },
    }));

    return { paths, fallback: false }
}

export default Host;