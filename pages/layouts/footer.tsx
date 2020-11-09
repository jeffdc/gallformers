import React from 'react';
import { Nav, Navbar } from 'react-bootstrap';

const Footer = (): JSX.Element => {
    return (
        <div className="">
            <Navbar collapseOnSelect expand="lg" bg="light" variant="light">
                <Nav.Link className="ml-auto" href="/about">
                    About
                </Nav.Link>
            </Navbar>
        </div>
    );
};

export default Footer;
