import Head from 'next/head';

import { Navbar, Nav, Form, FormControl, Button } from 'react-bootstrap';

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

//   <nav class="navbar navbar-expand-sm bg-dark navbar-dark justify-content-end">
//     <a class="navbar-brand" href="#">Home</a>
//     <button class="btn btn-success ml-auto mr-1">Always Show</button>
//     <button class="navbar-toggler" type="button" data-toggle="collapse" data-target="#navbarSupportedContent">
//         <span class="navbar-toggler-icon"></span>
//     </button>
//     <div class="collapse navbar-collapse flex-grow-0" id="navbarSupportedContent">
//         <ul class="navbar-nav text-right">
//             <li class="nav-item active">
//                 <a class="nav-link" href="#">Right Link 1</a>
//             </li>
//             <li class="nav-item active">
//                 <a class="nav-link" href="#">Right Link 2</a>
//             </li>
//         </ul>
//     </div>
// </nav>