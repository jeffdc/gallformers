import 'bootstrap/dist/css/bootstrap.min.css';
import { SessionProvider } from 'next-auth/react';
import { AppProps } from 'next/app';
import Head from 'next/head';
import React from 'react';
import { Col, Container, Row } from 'react-bootstrap';
import 'react-bootstrap-typeahead/css/Typeahead.css';
import 'react-bootstrap-typeahead/css/Typeahead.bs5.css';
import { ConfirmationServiceProvider } from '../hooks/useConfirmation';
import Footer from '../layouts/footer';
import Header from '../layouts/header';
import './style.scss';
import { StyleSheetManager } from 'styled-components';
import isPropValid from '@emotion/is-prop-valid';

// This implements the default behavior from styled-components v5
function shouldForwardProp(propName: string, target: unknown) {
    if (typeof target === 'string') {
        // For HTML elements, forward the prop if it is a valid HTML attribute
        return isPropValid(propName);
    }
    // For other elements, forward all props
    return true;
}

function Gallformers({ Component, pageProps }: AppProps): JSX.Element {
    return (
        <StyleSheetManager shouldForwardProp={shouldForwardProp}>
            {/* eslint-disable-next-line @typescript-eslint/no-unsafe-assignment, @typescript-eslint/no-unsafe-member-access */}
            <SessionProvider session={pageProps.session}>
                <Container fluid className="p-0 m-0">
                    <Head>
                        {/* <script type="text/javascript"> */}
                        {/* Fix for Firefox autofocus CSS bug See:
                        http://stackoverflow.com/questions/18943276/html-5-autofocus-messes-up-css-loading/18945951#18945951 */}
                        {/* </script> */}

                        <title>Gallformers</title>
                        <link rel="icon" href="/favicon.ico" />
                        <meta
                            name="description"
                            content="The place to ID and learn about galls on plants in the US and Canada."
                        />
                    </Head>
                    <Row>
                        <Col className="m-0 p-0">
                            <Header />
                        </Col>
                    </Row>
                    <Row>
                        <Col className="m-3 mb-5 p-2">
                            <ConfirmationServiceProvider>
                                <Component {...pageProps} />
                            </ConfirmationServiceProvider>
                        </Col>
                    </Row>
                    <Row>
                        <Col className="m-0 p-0">
                            <Footer />
                        </Col>
                    </Row>
                </Container>
            </SessionProvider>
        </StyleSheetManager>
    );
}

export default Gallformers;
