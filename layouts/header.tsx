import Head from 'next/head';
import { useRouter } from 'next/router';
import React, { KeyboardEvent, SyntheticEvent, useState } from 'react';
import { Button, Container, Form, FormControl, Nav, Navbar, NavDropdown } from 'react-bootstrap';

const Header = (): JSX.Element => {
    const [searchText, setSearchText] = useState('');
    const router = useRouter();

    const submitSearch = (e: SyntheticEvent) => {
        e.preventDefault();
        if (searchText) {
            router.push({
                pathname: '/globalsearch',
                query: {
                    searchText: searchText,
                },
            });
        }
    };

    const handleSearchKeyUp = (event: KeyboardEvent<HTMLInputElement>) => {
        if (event.key === 'Enter' && event.keyCode === 13) {
            submitSearch(event);
        }
    };

    return (
        <>
            <Head>
                <title>Gallformers</title>
                <link rel="icon" href="/favicon.ico" />
            </Head>
            <Navbar sticky="top" collapseOnSelect expand="md" className="navbar-custom" variant="dark" p-0 m-0>
                <Container fluid>
                    <Navbar.Brand href="/">
                        {/* eslint-disable-next-line @next/next/no-img-element */}
                        <img
                            src="/branding/Wide Logo Versions/gallformers_logo_wide_color.png"
                            height="70px"
                            // className="d-inline-block"
                            alt="The gallformers logo: an oak gall wasp with a spherical oak gall and a white oak leaf."
                        />
                    </Navbar.Brand>
                    <Navbar.Toggle aria-controls="responsive-navbar-nav">
                        <i className="hamburger" />
                    </Navbar.Toggle>
                    <Navbar.Collapse id="responsive-navbar-nav">
                        <Nav className="ms-auto my-0 my-lg-0">
                            <Nav.Link href="/id">Identify</Nav.Link>
                            <Nav.Link href="/explore">Explore</Nav.Link>
                            <Form
                                onSubmit={(e) => {
                                    submitSearch(e);
                                }}
                                className="d-flex"
                            >
                                <FormControl
                                    onChange={(e) => {
                                        setSearchText(e.target.value);
                                    }}
                                    value={searchText}
                                    onKeyUp={handleSearchKeyUp}
                                    type="search"
                                    placeholder="Search"
                                    className="me-2"
                                    aria-label="Search"
                                />
                                <Button type="submit" variant="outline-light" className="search-button">
                                    Search
                                </Button>
                            </Form>
                            <NavDropdown title="Resources">
                                <NavDropdown.Item href="/filterguide">Filter Terms</NavDropdown.Item>
                                <NavDropdown.Item href="/glossary">Glossary</NavDropdown.Item>
                                <NavDropdown.Item href="/refindex">Reference</NavDropdown.Item>
                            </NavDropdown>
                        </Nav>
                    </Navbar.Collapse>
                </Container>
            </Navbar>
        </>
    );
};

export default Header;
