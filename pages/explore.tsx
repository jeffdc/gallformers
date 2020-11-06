import { family, gall, PrismaClient, species } from '@prisma/client';
import { GetStaticProps } from 'next';
import Link from 'next/link';
import { Accordion, Button, Card, ListGroup, Tab, Tabs } from 'react-bootstrap';

type Species = species & {
    gall: gall[]
}
type Family = family & {
    species: Species[]
}
type Props = {
    gallmakers: Family[],
    hosts: Family[]
}

const gallLister = (f: Family) => {
    return f.species.map( s =>
        s.gall.map( g =>
            <ListGroup.Item key={g.species_id}>
                <Link href={"gall/[id]"} as={`gall/${g.species_id}`}><a>{s.name}</a></Link>
            </ListGroup.Item>   
        )
    ).flat()
}

const hostLister = (f: Family) => {
    return f.species.map( s =>
        <ListGroup.Item key={s.id}>
            <Link href={"host/[id]"} as={`host/${s.id}`}><a>{s.name}</a></Link>
        </ListGroup.Item>   
    )
}

const renderList = (data: Family[], lister: (f: Family) => JSX.Element[]) => {
    return data.map( (f) =>
        <Card key={f.id}>
            <Card.Header>
                <Accordion.Toggle as={Button} variant="light" eventKey={f.id.toString()}>
                    <i>{f.name}</i> - {f.description}
                </Accordion.Toggle>
            </Card.Header>
            <Accordion.Collapse eventKey={f.id.toString()}>
                <Card.Body>
                    <ListGroup>
                        { lister(f) }
                    </ListGroup>
                </Card.Body>
            </Accordion.Collapse>
        </Card>
    )
}

const Explore = ({gallmakers, hosts}: Props): JSX.Element => {
    return (
        <Card>
        <Card.Header>
            <Tabs defaultActiveKey="galls">
                <Tab eventKey="galls" title="Galls">
                    <Card.Body>
                    <Card.Title>Browse Galls</Card.Title>
                    <Card.Text>
                        By Family
                    </Card.Text>
                    <Accordion>
                        {renderList(gallmakers, gallLister)}
                    </Accordion>
                    </Card.Body>
                </Tab>
                <Tab eventKey="hosts" title="Hosts">
                <Card.Body>
                    <Card.Title>Browse Hosts</Card.Title>
                    <Card.Text>
                        By Family
                    </Card.Text>
                    <Accordion>
                        {renderList(hosts, hostLister)}
                    </Accordion>
                    </Card.Body>
                </Tab>
            </Tabs>
        </Card.Header>
        </Card>
    )
}

// Use static so that this stuff can be built once on the server-side and then cached.
export const getStaticProps: GetStaticProps = async () => {
    const newdb = new PrismaClient();
    const gallmakers = await newdb.family.findMany({
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

    const hosts = await newdb.family.findMany({
        include: {
            species: {
                select: {
                    id: true,
                    name: true
                },
                orderBy: { name: 'asc' }
            },
        },
        orderBy: { name: 'asc' },
        where: { description: { equals: "Plant" }}
    });

    return { props: {
           gallmakers: gallmakers,
           hosts: hosts,
        }
    }
}

export default Explore;