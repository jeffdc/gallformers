import 'bootstrap/dist/css/bootstrap.min.css';
import { SessionProvider } from 'next-auth/react';
import { AppProps } from 'next/app.js';
import Head from 'next/head.js';
import React from 'react';
import { Col, Container, Row } from 'react-bootstrap';
import 'react-bootstrap-typeahead/css/Typeahead.css';
import 'react-bootstrap-typeahead/css/Typeahead.bs5.css';
import { ConfirmationServiceProvider } from '../hooks/useConfirmation.js';
import Footer from '../layouts/footer.js';
import Header from '../layouts/header.js';
import './style.scss';

function Gallformers({ Component, pageProps }: AppProps): JSX.Element {
    return (
        <SessionProvider session={pageProps.session}>
            <Container fluid className="p-0 m-0">
                <Head.default>
                    {/* <script type="text/javascript"> */}
                    {/* Fix for Firefox autofocus CSS bug See:
                        http://stackoverflow.com/questions/18943276/html-5-autofocus-messes-up-css-loading/18945951#18945951 */}
                    {/* </script> */}

                    <title>Gallformers</title>
                    <link rel="icon" href="/favicon.ico" />
                    <meta name="description" content="The place to ID and learn about galls on plants in the US and Canada." />
                </Head.default>
                <Row>
                    <Col className="m-0 p-0">
                        <Header />
                    </Col>
                </Row>
                <Row>
                    <Col className="ms-5 me-5 p-2">
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
    );
}

export default Gallformers;
