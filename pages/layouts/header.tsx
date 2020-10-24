import Head from 'next/head';
import { Button, Form, FormControl, Nav, Navbar } from 'react-bootstrap';

const Header = () => (
    <div style={{
        marginBottom: '5%'
    }}>
    <Head>
        <title>Gallformers</title>
        <link rel="icon" href="/favicon.ico" />
    </Head>
    <Navbar fixed="top" collapseOnSelect expand="lg" bg="dark" variant="dark">
        <Navbar.Brand href="/">Gallformers</Navbar.Brand>
        <Nav.Link href="/id">Id</Nav.Link>
        <Nav.Link href="/explore">Explore</Nav.Link>
        <Form inline>
            <FormControl type="text" placeholder="search" className="mr-sm-2" />
            <Button variant="outline-success">Search</Button>
        </Form>
    </Navbar>
    </div>
  );
  
  export default Header;