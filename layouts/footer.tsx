import { useAuth0 } from '@auth0/auth0-react';
import React from 'react';
import { Nav, Navbar, NavbarBrand } from 'react-bootstrap';
import LogoutButton from '../components/logout';

const Footer = (): JSX.Element => {
    const { user, isAuthenticated, isLoading } = useAuth0();

    const logoff = () => {
        if (isAuthenticated && !isLoading) {
            return <LogoutButton />;
        } else {
            <></>;
        }
    };

    return (
        <div className="">
            <Navbar collapseOnSelect expand="lg" bg="light" variant="light">
                <NavbarBrand>
                    {isAuthenticated && <img src={user.picture} alt={user.name} width="25px" height="25px" />}
                </NavbarBrand>
                <Nav>{logoff()}</Nav>
                <Nav.Link className="ml-auto" href="/about">
                    About
                </Nav.Link>
            </Navbar>
        </div>
    );
};

export default Footer;
