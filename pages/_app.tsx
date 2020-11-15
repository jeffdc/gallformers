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
    );
}

export default Gallformers;
