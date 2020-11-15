import Head from 'next/head';
import { useRouter } from 'next/router';
import React, { KeyboardEvent, useState } from 'react';
import { Button, Form, FormControl, Nav, Navbar, OverlayTrigger, Tooltip } from 'react-bootstrap';

const Header = (): JSX.Element => {
    const [searchText, setSearchText] = useState('');
    const router = useRouter();

    const submitSearch = () => {
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
        event.preventDefault();
        if (event.key === 'Enter' && event.keyCode === 13) {
            submitSearch();
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
            <Navbar fixed="top" collapseOnSelect expand="lg" bg="dark" variant="dark">
                <Navbar.Brand href="/">
                    <img src="./images/fly.svg" width="25px" height="25px" /> Gallformers
                </Navbar.Brand>
                <Nav.Link href="/id">Id</Nav.Link>
                <Nav.Link href="/explore">Explore</Nav.Link>
                <Form inline onSubmit={(e) => e.preventDefault()} className="ml-auto">
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
                    <Button variant="outline-success">Search</Button>
                </Form>
                <OverlayTrigger placement="bottom" overlay={<Tooltip id="glossary">Glossary</Tooltip>}>
                    <Nav.Link href="/glossary">?</Nav.Link>
                </OverlayTrigger>
            </Navbar>
        </div>
    );
};

export default Header;
