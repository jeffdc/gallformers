import 'bootstrap/dist/css/bootstrap.min.css';
import { Provider } from 'next-auth/client';
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
        <Provider session={pageProps.session}>
            <div className="Layout" style={layoutStyle}>
                <Head>
                    <script type="text/javascript">
                        {/* Fix for Firefox autofocus CSS bug See:
                        http://stackoverflow.com/questions/18943276/html-5-autofocus-messes-up-css-loading/18945951#18945951 */}
                    </script>

                    <title>Gallformers</title>
                    <link rel="icon" href="/favicon.ico" />
                </Head>
                <Header />
                <div style={contentStyle}>
                    <Component {...pageProps} />
                </div>
                <Footer />
            </div>
        </Provider>
    );
}

export default Gallformers;
