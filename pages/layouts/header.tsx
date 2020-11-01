import Head from 'next/head';
import { useRouter } from 'next/router';
import React, { KeyboardEvent, useState } from 'react';
import { Button, Form, FormControl, Nav, Navbar, OverlayTrigger, Tooltip } from 'react-bootstrap';

export function pickIcon(): JSX.Element {
    if (Date.now() % 2 == 0) {
        return (
            <svg width="1.25em" height="1.25em" viewBox="0 0 16 16" className="bi bi-tree d-inline-block align-middle"          
                 fill="currentColor" xmlns="http://www.w3.org/2000/svg">
                    <path fillRule="evenodd" d="M8 0a.5.5 0 0 1 .416.223l3 4.5A.5.5 0 0 1 11 5.5h-.098l2.022 3.235a.5.5 0 0 1-.424.765h-.191l1.638 3.276a.5.5 0 0 1-.447.724h-11a.5.5 0 0 1-.447-.724L3.69 9.5H3.5a.5.5 0 0 1-.424-.765L5.098 5.5H5a.5.5 0 0 1-.416-.777l3-4.5A.5.5 0 0 1 8 0zM5.934 4.5H6a.5.5 0 0 1 .424.765L4.402 8.5H4.5a.5.5 0 0 1 .447.724L3.31 12.5h9.382l-1.638-3.276A.5.5 0 0 1 11.5 8.5h.098L9.576 5.265A.5.5 0 0 1 10 4.5h.066L8 1.401 5.934 4.5z"/>
                    <path d="M7 13.5h2V16H7v-2.5z"/>
            </svg>
        )
    } else {
        return (
            <svg width="1.25em" height="1.25em" viewBox="0 0 16 16" className="bi bi-bug d-inline-block align-middle" 
                 fill="currentColor" xmlns="http://www.w3.org/2000/svg">
                <path fillRule="evenodd" d="M4.355.522a.5.5 0 0 1 .623.333l.291.956A4.979 4.979 0 0 1 8 1c1.007 0 1.946.298 2.731.811l.29-.956a.5.5 0 1 1 .957.29l-.41 1.352A4.985 4.985 0 0 1 13 6h.5a.5.5 0 0 0 .5-.5V5a.5.5 0 0 1 1 0v.5A1.5 1.5 0 0 1 13.5 7H13v1h1.5a.5.5 0 0 1 0 1H13v1h.5a1.5 1.5 0 0 1 1.5 1.5v.5a.5.5 0 1 1-1 0v-.5a.5.5 0 0 0-.5-.5H13a5 5 0 0 1-10 0h-.5a.5.5 0 0 0-.5.5v.5a.5.5 0 1 1-1 0v-.5A1.5 1.5 0 0 1 2.5 10H3V9H1.5a.5.5 0 0 1 0-1H3V7h-.5A1.5 1.5 0 0 1 1 5.5V5a.5.5 0 0 1 1 0v.5a.5.5 0 0 0 .5.5H3c0-1.364.547-2.601 1.432-3.503l-.41-1.352a.5.5 0 0 1 .333-.623zM4 7v4a4 4 0 0 0 3.5 3.97V7H4zm4.5 0v7.97A4 4 0 0 0 12 11V7H8.5zM12 6H4a3.99 3.99 0 0 1 1.333-2.982A3.983 3.983 0 0 1 8 2c1.025 0 1.959.385 2.666 1.018A3.989 3.989 0 0 1 12 6z"/>
            </svg>
        )
    }
}

const Header = (): JSX.Element => {
    const [searchText, setSearchText] = useState("");
    const router = useRouter();
    
    const submitSearch = () => {
        if (searchText) {
            router.push({
                pathname: '/globalsearch',
                query: { 
                    searchText: searchText 
                },
            });
        }
    }
    
    const handleSearchKeyUp = (event: KeyboardEvent<HTMLInputElement>) => {
        event.preventDefault();
        if (event.key === 'Enter' && event.keyCode === 13) {
            submitSearch();
        }
    }
    
    return (
        <div style={{
            marginBottom: '5%'
        }}>
        <Head>
            <title>Gallformers</title>
            <link rel="icon" href="/favicon.ico" />
        </Head>
        <Navbar fixed="top" collapseOnSelect expand="lg" bg="dark" variant="dark">
            <Navbar.Brand href="/">
                {pickIcon()}
                { ' ' }
                Gallformers
            </Navbar.Brand>
            <Nav.Link href="/id">Id</Nav.Link>
            <Nav.Link href="/explore">Explore</Nav.Link>
            <Form inline onSubmit={ e => e.preventDefault() } className="ml-auto">
                <FormControl 
                    onChange={ e => { setSearchText(e.target.value) } }
                    value={searchText}
                    onKeyUp={handleSearchKeyUp}
                    type="text" 
                    placeholder="Search" 
                    className="mr-sm-2" 
                />
                <Button variant="outline-success">Search</Button>
            </Form>
            <OverlayTrigger
                placement="bottom"
                overlay={
                    <Tooltip id='glossary'>Glossary</Tooltip>
                }
            >
                <Nav.Link href="/glossary">?</Nav.Link>
            </OverlayTrigger>
        </Navbar>
        </div>
  )};
  
  export default Header;