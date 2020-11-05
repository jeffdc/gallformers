import { family, gall, PrismaClient, species } from '@prisma/client';
import { GetStaticProps } from 'next';
import Link from 'next/link';
import { Accordion, Button, Card, ListGroup, Nav } from 'react-bootstrap';

type SpeciesProp = species & {
    gall: gall[]
}
type FamilyProp = family & {
    species: SpeciesProp[]
}
type Props = {
    families: FamilyProp[],
}

const Explore = ({families}: Props): JSX.Element => {
    return (
        <Card>
        <Card.Header>
            <Nav variant="tabs" defaultActiveKey="#first">
                <Nav.Item>
                    <Nav.Link href="#first">Galls</Nav.Link>
                </Nav.Item>
                <Nav.Item>
                    <Nav.Link href="#link">Hosts</Nav.Link>
                </Nav.Item>
            </Nav>
        </Card.Header>
        <Card.Body>
            <Card.Title>Browse Galls</Card.Title>
            <Card.Text>
                By Family
            </Card.Text>
            <Accordion>
                {families.map( (f) =>
                    <Card key={f.id}>
                        <Card.Header>
                            <Accordion.Toggle as={Button} variant="light" eventKey={f.id.toString()}>
                                <i>{f.name}</i> - {f.description}
                            </Accordion.Toggle>
                        </Card.Header>
                        <Accordion.Collapse eventKey={f.id.toString()}>
                            <Card.Body>
                                <ListGroup>
                                    { f.species.map( s =>
                                        s.gall.map( g =>
                                            <ListGroup.Item key={g.species_id}>
                                                <Link href={"gall/[id]"} as={`gall/${g.species_id}`}><a>{s.name}</a></Link>
                                            </ListGroup.Item>   
                                        )
                                    )}
                                </ListGroup>
                            </Card.Body>
                        </Accordion.Collapse>
                    </Card>
                )}
            </Accordion>
        </Card.Body>
        </Card>
    )
}

// Use static so that this stuff can be built once on the server-side and then cached.
export const getStaticProps: GetStaticProps = async () => {
    const newdb = new PrismaClient();
    const families = await newdb.family.findMany({
        include: {
            species: {
                select: {
                    id: true,
                    name: true,
                    gall: {
                        select: {
                            species_id: true,
                        },
                    },
                },
                orderBy: { name: 'asc' },
            },
        },
        orderBy: { name: 'asc' },
        where: { description: { not: "Plant" }}
    });

    return { props: {
           families:  families,
        }
    }
}

export default Explore;