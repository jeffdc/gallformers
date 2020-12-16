import { GetStaticProps } from 'next';
import Link from 'next/link';
import { Accordion, Button, Card, ListGroup, Tab, Tabs } from 'react-bootstrap';
import { FamilyWithSpecies } from '../libs/api/apitypes';
import { getGallMakerFamilies, getHostFamilies } from '../libs/db/family';
import { getStaticPropsWith } from '../libs/pages/nextPageHelpers';

type Props = {
    gallmakers: FamilyWithSpecies[];
    hosts: FamilyWithSpecies[];
};

const lister = (f: FamilyWithSpecies, gall: boolean) => {
    const path = gall ? 'gall' : 'host';
    return f.species.map((s) => (
        <ListGroup.Item key={s.id}>
            <Link href={`${path}/${s.id}`}>
                <a>{s.name}</a>
            </Link>
        </ListGroup.Item>
    ));
};

const renderList = (data: FamilyWithSpecies[], gall: boolean) => {
    return data.map((f) => (
        <Card key={f.id}>
            <Card.Header>
                <Accordion.Toggle as={Button} variant="light" eventKey={f.id.toString()}>
                    <i>{f.name}</i> - {f.description}
                </Accordion.Toggle>
            </Card.Header>
            <Accordion.Collapse eventKey={f.id.toString()}>
                <Card.Body>
                    <ListGroup>{lister(f, gall)}</ListGroup>
                </Card.Body>
            </Accordion.Collapse>
        </Card>
    ));
};

const Explore = ({ gallmakers, hosts }: Props): JSX.Element => {
    return (
        <Card>
            <Card.Header>
                <Tabs defaultActiveKey="galls">
                    <Tab eventKey="galls" title="Galls">
                        <Card.Body>
                            <Card.Title>Browse Galls</Card.Title>
                            <Card.Text>By Family</Card.Text>
                            <Accordion>{renderList(gallmakers, true)}</Accordion>
                        </Card.Body>
                    </Tab>
                    <Tab eventKey="hosts" title="Hosts">
                        <Card.Body>
                            <Card.Title>Browse Hosts</Card.Title>
                            <Card.Text>By Family</Card.Text>
                            <Accordion>{renderList(hosts, false)}</Accordion>
                        </Card.Body>
                    </Tab>
                </Tabs>
            </Card.Header>
        </Card>
    );
};

// Use static so that this stuff can be built once on the server-side and then cached.
export const getStaticProps: GetStaticProps = async () => {
    return {
        props: {
            gallmakers: await getStaticPropsWith(getGallMakerFamilies, 'gall families'),
            hosts: await getStaticPropsWith(getHostFamilies, 'host familes'),
        },
        revalidate: 1,
    };
};

export default Explore;
