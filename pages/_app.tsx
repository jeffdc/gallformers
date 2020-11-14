import { Auth0Provider } from '@auth0/auth0-react';
import 'bootstrap/dist/css/bootstrap.min.css';
import { AppProps } from 'next/app';
import Head from 'next/head';
import React, { CSSProperties } from 'react';
import 'react-bootstrap-typeahead/css/Typeahead.css';
import Footer from '../layouts/footer';
import Header from '../layouts/header';

const layoutStyle: CSSProperties = {
    display: 'flex',
    flexDirection: 'column',
    minHeight: '100vh',
};

const contentStyle: CSSProperties = {
    flex: 1,
    display: 'flex',
    flexDirection: 'column',
};

function Gallformers({ Component, pageProps }: AppProps): JSX.Element {
    return (
        <Auth0Provider
            domain={'dev-sur--xbk.us.auth0.com'}
            clientId={'UfsN055usaBcyW2UrEKfH2y78IMzZgw6'}
            redirectUri={`${process.env.APP_URL}/admin`}
        >
            <div className="Layout" style={layoutStyle}>
                <Head>
                    <title>Gallformers</title>
                    <link rel="icon" href="/favicon.ico" />
                </Head>
                <Header />
                <div style={contentStyle}>
                    <Component {...pageProps} />
                </div>
                <Footer />
            </div>
        </Auth0Provider>
    );
}

export default Gallformers;
