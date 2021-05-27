import 'bootstrap/dist/css/bootstrap.min.css';
import { Provider } from 'next-auth/client';
import { AppProps } from 'next/app';
import Head from 'next/head';
import React from 'react';
import { Col, Container, Row } from 'react-bootstrap';
import 'react-bootstrap-typeahead/css/Typeahead.css';
import { ConfirmationServiceProvider } from '../hooks/useconfirmation';
import Footer from '../layouts/footer';
import Header from '../layouts/header';
import './style.scss';

function Gallformers({ Component, pageProps }: AppProps): JSX.Element {
    return (
        <Provider session={pageProps.session}>
            <Container fluid className="pt-4">
                <Head>
                    <script type="text/javascript">
                        {/* Fix for Firefox autofocus CSS bug See:
                        http://stackoverflow.com/questions/18943276/html-5-autofocus-messes-up-css-loading/18945951#18945951 */}
                    </script>

                    <title>Gallformers</title>
                    <link rel="icon" href="/favicon.ico" />
                    <meta
                        name="gallformers"
                        content="Gallformers is the site to help identitfy galls on plants in North America."
                    />
                </Head>
                <Row>
                    <Col>
                        <Header />
                    </Col>
                </Row>
                <Row className="pb-5 mb-5">
                    <Col>
                        <ConfirmationServiceProvider>
                            <Component {...pageProps} />
                        </ConfirmationServiceProvider>
                    </Col>
                </Row>
                <Footer />
            </Container>
        </Provider>
    );
}

export default Gallformers;
