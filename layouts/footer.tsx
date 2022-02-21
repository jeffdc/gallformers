import { signOut, useSession } from 'next-auth/react';
import React from 'react';
import { Button, Nav, Navbar } from 'react-bootstrap';
import { sessionUserOrUnknown } from '../libs/utils/util';

const Footer = (): JSX.Element => {
    const { data: session } = useSession();

    const logoff = () => {
        return (
            /* eslint-disable-next-line @typescript-eslint/no-explicit-any */
            <Button variant="outline-secondary" size="sm" onClick={signOut as any}>
                Log Off
            </Button>
        );
    };

    return (
        <Navbar expand="md" bg="light" variant="light" fixed="bottom" className="darklogotext">
            <Navbar.Toggle aria-controls="navbarScroll" />
            {session && (
                <Navbar.Collapse>
                    <Nav.Item className="px-2">
                        {/* eslint-disable-next-line @next/next/no-img-element */}
                        <img
                            src={session?.user?.image == null ? undefined : session.user.image}
                            alt={sessionUserOrUnknown(session?.user?.name)}
                            width="25px"
                            height="25px"
                        />
                    </Nav.Item>
                    <Navbar.Text className="px-0">{sessionUserOrUnknown(session?.user?.name)}</Navbar.Text>
                    <Nav.Item className="ps-2">{logoff()}</Nav.Item>
                    <Nav.Link href="/admin">Admin</Nav.Link>
                </Navbar.Collapse>
            )}
            <Nav.Link href="/about" className="justify-content-end">
                About
            </Nav.Link>
        </Navbar>
    );
};

export default Footer;
