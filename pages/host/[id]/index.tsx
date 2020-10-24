import { abundance, family, gall, host, PrismaClient, species } from '@prisma/client';
import Link from 'next/link';
import React from 'react';
import { Col, Container, Media, Row } from 'react-bootstrap';

type GallProp = gall & {
    species: species
}

type HostSpeciesProp = species & {
    family: family,
    abundance: abundance,
    host_galls: GallProp[]
}
type HostProps = host & {
    hostspecies: HostSpeciesProp
}
type Props = {
    host: HostProps
}

function gallAsLink(g: GallProp) {
    return ( <Link key={g.species_id} href={"/gall/[id]"} as={`/gall/${g.species_id}`}><a>{g.species.name} </a></Link> )
}

const Host = ({ host }: Props) => {
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
                alt={host.hostspecies.name}
            />
            <Media.Body>
                <Container className='p-3 border'>
                    <Row>
                        <Col><h1>{host.hostspecies.name}</h1></Col>
                        <Col className='text-right font-italic'>Family: {host.hostspecies.family.name}</Col>
                    </Row>
                    <Row>
                        <Col className='lead p-3'>{host.hostspecies.description}</Col>
                    </Row>
                    <Row>
                        <Col>
                            Galls: { host.hostspecies.host_galls.map(gallAsLink) }
                        </Col>
                    </Row>
                    <Row>
                        <Col>Abdundance: {host.hostspecies.abundance}</Col>
                    </Row>
                </Container>
            </Media.Body>
        </Media>
    </div>
  )
};


// Use static so that this stuff can be built once on the server-side and then cached.
export async function getStaticProps(context: { params: { id: string; }; }) {
    const newdb = new PrismaClient();
    const host = await newdb.host.findFirst({
        include: {
            hostspecies: {
                include: {
                    abundance: true,
                    family: true,
                    host_galls: {
                        include: {
                            species: true,
                        }
                    }
                }
            }
        },
        where: { host_species_id: { equals: parseInt(context.params.id) } }
    });

    return { props: {
           host: host,
        }
    }
}

export async function getStaticPaths() {
    const newdb = new PrismaClient();
    const hosts = await newdb.host.findMany({
        include: {
            hostspecies: {
                select: {
                    species_id: true,
                }
            }
        }
    });

    const paths = hosts.map((host) => ({
        params: { id: host.host_species_id.toString() },
    }));

    return { paths, fallback: false }
}

export default Host;