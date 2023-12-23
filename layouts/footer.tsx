import { signOut, useSession } from 'next-auth/react';
import React from 'react';
import { Button, Nav, Navbar } from 'react-bootstrap';
import useIsMounted from '../hooks/useIsMounted.js';
import { sessionUserOrUnknown } from '../libs/utils/util.js';

const Footer = (): JSX.Element => {
    const { data: session } = useSession();
    const mounted = useIsMounted();

    const logoff = () => {
        return (
            /* eslint-disable-next-line @typescript-eslint/no-explicit-any */
            <Button variant="outline-secondary" size="sm" onClick={signOut as any}>
                Log Off
            </Button>
        );
    };

    return (
        <Navbar expand="sm" variant="dark" collapseOnSelect className="navbar-footer container-fluid px-4">
            <Navbar.Collapse>
                {mounted && session && (
                    <>
                        <Nav.Item className="px-2">
                            <img
                                src={session?.user?.image == null ? undefined : session.user.image}
                                alt={sessionUserOrUnknown(session?.user?.name)}
                                width="25px"
                                height="25px"
                            />
                        </Nav.Item>
                        <Navbar.Text className="px-2">{sessionUserOrUnknown(session?.user?.name)}</Navbar.Text>
                        <Nav.Item className="ps-2">{logoff()}</Nav.Item>
                    </>
                )}
                <Nav.Link href="https://www.patreon.com/gallformers" target="__blank" rel="noreferrer" className="ms-auto px-2">
                    Donate
                </Nav.Link>
                <Nav.Link href="/about" className="justify-content-end px-2">
                    About
                </Nav.Link>
            </Navbar.Collapse>
            <Navbar.Toggle aria-controls="responsive-navbar-nav">
                <i className="hamburger" />
            </Navbar.Toggle>
        </Navbar>
    );
};

export default Footer;
