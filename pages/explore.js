import Link from 'next/link';
import { Card, Nav, Button, ListGroup, ListGroupItem } from 'react-bootstrap';

const Explore = ({families}) => {
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
            <ListGroup>
            {families.map( (f) =>
                <ListGroup.Item key={f.family}>
                    <Link href={"family/[id]"} as={`family/${f.family}`}><a>{f.family}</a></Link>
                </ListGroup.Item>   
            )}
            </ListGroup>
        </Card.Body>
        </Card>
    )
}

// Use static so that this stuff can be built once on the server-side and then cached.
export async function getStaticProps() {
    const response = await fetch('http://localhost:3000/api/gall/families');
    const families = await response.json();

    return { props: {
           families: families,
        }
    }
}

export default Explore;