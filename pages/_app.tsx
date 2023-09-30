import 'bootstrap/dist/css/bootstrap.min.css';
import { SessionProvider } from 'next-auth/react';
import { AppProps } from 'next/app';
import Head from 'next/head';
import React from 'react';
import { Col, Container, Row, SSRProvider } from 'react-bootstrap';
import 'react-bootstrap-typeahead/css/Typeahead.css';
import 'react-bootstrap-typeahead/css/Typeahead.bs5.css';
import { ConfirmationServiceProvider } from '../hooks/useconfirmation';
import Footer from '../layouts/footer';
import Header from '../layouts/header';
import './style.scss';

function Gallformers({ Component, pageProps }: AppProps): JSX.Element {
    return (
        <SSRProvider>
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
                        <Col classNme="m-0 p-0">
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
        </SSRProvider>
    );
}

export default Gallformers;
