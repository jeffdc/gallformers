import Link from 'next/link';
import { Card, Nav, Button, ListGroup, Accordion } from 'react-bootstrap';
import { array } from 'yup';

const Explore = ({families, gallsByFamily}) => {
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
                    <Card key={f.family_id}>
                        <Card.Header>
                            <Accordion.Toggle as={Button} variant="light" eventKey={f.family_id}>
                                <i>{f.name}</i> - {f.description}
                            </Accordion.Toggle>
                        </Card.Header>
                        <Accordion.Collapse eventKey={f.family_id}>
                            <Card.Body>
                                <ListGroup>
                                    {gallsByFamily[f.name].map( (g) =>
                                        <ListGroup.Item key={g.species_id}>
                                            <Link href={"gall/[id]"} as={`gall/${g.species_id}`}><a>{g.name}</a></Link>
                                        </ListGroup.Item>   
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
export async function getStaticProps() {
    // hack to avoid tree-shaking issue in next.js. see:
    // https://github.com/vercel/next.js/issues/16153) and https://github.com/prisma/prisma/issues/3252
    const { newdb } = require('../database');

    const galls = await newdb.gall.findMany({
        include: {
            species: {
                select: {
                    name: true, 
                    synonyms: true, 
                    commonnames: true, 
                    genus: true, 
                    description: true,
                    family: { select: { name: true } }
                }
            },
            location: {},
            color: {},
            alignment: {},
            shape: {},
            walls: {},
            cells: {},
            texture: {}
        }
    });
    function familyToGall(acc, gall) {
        const familyname = gall.species.family.name;
        if (acc[familyname]) {
            acc[familyname].push(gall)
        } else {
            acc[familyname] = [gall]
        }
        return acc;
    }

    const gallsByFamily = galls.reduce(familyToGall, {});
    gallsByFamily.map(g => console.log(g));
    return { props: {
           families:  gallsByFamily.map(g => g),
           gallsByFamily: gallsByFamily,
        }
    }
}

export default Explore;