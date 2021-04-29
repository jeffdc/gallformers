import Head from 'next/head';
import { useRouter } from 'next/router';
import React, { KeyboardEvent, SyntheticEvent, useState } from 'react';
import { Button, Dropdown, Form, FormControl, Nav, Navbar } from 'react-bootstrap';

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
            <Navbar fixed="top" collapseOnSelect expand="sm" bg="dark" variant="dark">
                <Navbar.Brand href="/">
                    <img src="/images/fly.svg" width="25px" height="25px" /> Gallformers
                </Navbar.Brand>
                <Navbar.Toggle aria-controls="responsive-navbar-nav" />
                <Navbar.Collapse id="responsive-navbar-nav">
                    <Nav className="ml-auto">
                        <Nav.Link href="/id" className="ml-auto">
                            Id
                        </Nav.Link>
                        <Nav.Link href="/explore" className="ml-auto">
                            Explore
                        </Nav.Link>
                        <Form
                            inline
                            onSubmit={(e) => {
                                submitSearch(e);
                            }}
                            className="ml-auto"
                        >
                            <FormControl
                                onChange={(e) => {
                                    setSearchText(e.target.value);
                                }}
                                value={searchText}
                                onKeyUp={handleSearchKeyUp}
                                type="text"
                                placeholder="Search"
                                className="mr-sm-2"
                            />
                            <Button type="submit" variant="outline-success" className="ml-auto">
                                Search
                            </Button>
                        </Form>
                        <Dropdown>
                            <Dropdown.Toggle
                                className="border border-success rounded m-1"
                                id="resources-button"
                                variant="outline-success"
                            >
                                Resources
                            </Dropdown.Toggle>
                            <Dropdown.Menu align="right">
                                <Dropdown.Item href="/guide">ID Guide</Dropdown.Item>
                                <Dropdown.Item href="/filterguide">Filter Terms</Dropdown.Item>
                                <Dropdown.Item href="/glossary">Plant and Insect Glossary</Dropdown.Item>
                            </Dropdown.Menu>
                        </Dropdown>
                    </Nav>
                </Navbar.Collapse>
            </Navbar>
        </div>
    );
};

export default Header;
