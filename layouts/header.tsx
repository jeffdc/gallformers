import Head from 'next/head';
import Image from 'next/image';
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
        <div
            style={{
                marginBottom: '5%',
            }}
        >
            <Head>
                <title>Gallformers</title>
                <link rel="icon" href="/favicon.ico" />
            </Head>
            <Navbar fixed="top" collapseOnSelect expand="md" className="navbar-custom" variant="dark">
                <Container fluid>
                    <Navbar.Brand href="/">
                        {/* eslint-disable-next-line @next/next/no-img-element */}
                        <img
                            src="/images/leaf-logo.svg"
                            width="40px"
                            height="40px"
                            className="d-inline-block"
                            alt="The gallformers logo, an orange oak leaf."
                        />
                        <span className="ps-2" style={{ fontSize: 'larger' }}>
                            gallformers
                        </span>
                    </Navbar.Brand>
                    <Navbar.Toggle aria-controls="responsive-navbar-nav" />
                    <Navbar.Collapse id="responsive-navbar-nav">
                        <Nav className="ms-auto my-2 my-lg-0">
                            <Nav.Link href="/id">Id</Nav.Link>
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
                                <Button type="submit" variant="outline-light">
                                    Search
                                </Button>
                            </Form>
                            <NavDropdown title="Resources">
                                <NavDropdown.Item href="/guide">ID Guide</NavDropdown.Item>
                                <NavDropdown.Item href="/filterguide">Filter Terms</NavDropdown.Item>
                                <NavDropdown.Item href="/glossary">Glossary</NavDropdown.Item>
                            </NavDropdown>
                        </Nav>
                    </Navbar.Collapse>
                </Container>
            </Navbar>
        </div>
    );
};

export default Header;
