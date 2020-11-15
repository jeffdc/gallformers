import { signOut, useSession } from 'next-auth/client';
import React from 'react';
import { Nav, Navbar, NavbarBrand } from 'react-bootstrap';

const Footer = (): JSX.Element => {
    const [session, loading] = useSession();

    const logoff = () => {
        if (session && !loading) {
            /* eslint-disable-next-line @typescript-eslint/no-explicit-any */
            return <button onClick={signOut as any}>Log Off</button>;
        } else {
            <></>;
        }
    };

    return (
        <div className="">
            <Navbar collapseOnSelect expand="lg" bg="light" variant="light">
                <NavbarBrand>
                    {session && <img src={session.user.image} alt={session.user.name} width="25px" height="25px" />}
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
