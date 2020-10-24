import { abundance, alignment, cells, color, family, gall, host, location, PrismaClient, shape, source, species, speciessource, texture, walls } from '@prisma/client';
import Link from 'next/link';
import React from 'react';
import { Col, Container, ListGroup, Media, Row } from 'react-bootstrap';

type SourceProp = speciessource & {
    source: source
}
type HostProp = host & {
    hostspecies: species
}
type SpeciesProps = species & {
    abundance: abundance,
    family: family,
    hosts: HostProp[],
    speciessource: SourceProp[]
}
type GallProps = gall & {
    species: SpeciesProps,
    alignment: alignment,
    cells: cells,
    color: color,
    location: location,
    shape: shape,
    texture: texture,
    walls: walls
}
type Props = {
    gall: GallProps
}

function hostAsLink(h: HostProp) {
    return ( <Link key={h.host_species_id} href={"/host/[id]"} as={`/host/${h.host_species_id}`}><a>{h.hostspecies.name} </a></Link> )
}

const Gall = ({ gall }: Props) => {
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
                src="/images/gall.jpg"
                alt={gall.species.name}
            />
            <Media.Body>
                <Container className='p-3 border'>
                    <Row>
                        <Col><h1>{gall.species.name}</h1></Col>
                        <Col className='text-right font-italic'>Family: {gall.species.family.name}</Col>
                    </Row>
                    <Row>
                        <Col className='lead p-3'>{gall.species.description}</Col>
                    </Row>
                    <Row>
                        <Col>
                            Hosts: { gall.species.hosts.map(hostAsLink) }
                        </Col>
                    </Row>
                    <Row>
                        <Col>Detachable: {gall.detachable == 1 ? 'yes' : 'no'}</Col>
                        <Col>Texture: {gall.texture?.texture}</Col>
                        <Col>Color: {gall.color?.color}</Col>
                        <Col>Alignment: {gall.alignment?.alignment}</Col>
                    </Row>
                    <Row>
                        <Col>Location: {gall.location?.loc}</Col>
                        <Col>Walls: {gall.walls?.walls}</Col>
                        <Col>Abdundance: {gall.species?.abundance}</Col>
                        <Col>Shape: {gall.shape?.shape}</Col>
                    </Row>
                    <Row>
                        <Col>Further Information: 
                            <ListGroup>
                                {gall.species.speciessource.map((speciessource) =>
                                    <ListGroup.Item key={speciessource.source_id}>
                                        {
                                            speciessource.source.link === null || 
                                            speciessource.source.link === undefined ||
                                            speciessource.source.link.length === 0 ?
                                                speciessource.source.citation + " (no link)"
                                            :
                                                <a href={speciessource.source.link}>{speciessource.source.citation}</a>
                                        }
                                    </ListGroup.Item>
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


// Use static so that this stuff can be built once on the server-side and then cached.
export async function getStaticProps(context: { params: { id: string; }; }) {
    const newdb = new PrismaClient();
    const gall = await newdb.gall.findFirst({
        include: {
            species: {
                include: {
                    abundance: true,
                    family: true,
                    speciessource: {
                        include: {
                            source: true,
                        },
                    },
                    hosts: {
                        include: {
                            hostspecies: true,
                        },
                    },
                }
            },
            alignment: true,
            cells: true,
            color: true,
            location: true,
            shape: true,
            texture: true,
            walls: true,
        },
        where: {
            species_id: { equals: parseInt(context.params.id) }
        }
    });
    return { props: {
           gall: gall,
        }
    }
}

export async function getStaticPaths() {
    const newdb = new PrismaClient();
    const galls = await newdb.gall.findMany({
        select: {
            species_id: true
        }
    });

    const paths = galls.map((gall) => ({
        params: { id: gall.species_id.toString() },
    }));

    return { paths, fallback: false }
}

export default Gall;