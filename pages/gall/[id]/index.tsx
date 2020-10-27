import { abundance, alignment, cells, color, family, gall, galllocation, galltexture, host, location, PrismaClient, shape, source, species, speciessource, texture, walls } from '@prisma/client';
import { GetStaticPaths, GetStaticProps } from 'next';
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
type LocationProps = galllocation & {
    location: location
}
type TextureProps = galltexture & {
    texture: texture
}

type GallProps = gall & {
    species: SpeciesProps,
    alignment: alignment,
    cells: cells,
    color: color,
    galllocation: LocationProps[],
    shape: shape,
    galltexture: TextureProps[],
    walls: walls
}
type Props = {
    gall: GallProps
}

function hostAsLink(h: HostProp) {
    return ( <Link key={h.host_species_id} href={"/host/[id]"} as={`/host/${h.host_species_id}`}><a>{h.hostspecies.name} </a></Link> )
}

const Gall = ({ gall }: Props): JSX.Element => {
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
                        <Col className='text-right font-italic'>
                            Family: 
                            <Link key={gall.species.family.id} href={"/family/[id]"} as={`/family/${gall.species.family.id}`}>
                                <a> {gall.species.family.name}</a>
                            </Link>
                        </Col>
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
                        <Col>Texture: {gall.galltexture.map(t => t.texture).join(",")}</Col>
                        <Col>Color: {gall.color?.color}</Col>
                        <Col>Alignment: {gall.alignment?.alignment}</Col>
                    </Row>
                    <Row>
                        <Col>Location: {gall.galllocation.map(l => l.location.location).join(", ")}</Col>
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
export const getStaticProps: GetStaticProps = async (context) => {
    if (context === undefined || context.params === undefined || context.params.id === undefined) {
        throw new Error('An id must be passed to gall/[id]!');
    }
    
    const id = context.params.id as string;
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
            galllocation: {
                select: { location: true }
            },
            shape: true,
            galltexture: {
                select: { texture: true }
            },
            walls: true,
        },
        where: {
            species_id: { equals: parseInt(id) }
        }
    });

    return { props: {
           gall: gall,
        }
    }
}

export const getStaticPaths: GetStaticPaths = async () => {
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