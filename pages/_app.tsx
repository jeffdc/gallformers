import 'bootstrap/dist/css/bootstrap.min.css';
import { AppProps } from 'next/app';
import 'react-bootstrap-typeahead/css/Typeahead.css';
import Header from './layouts/header';

function Gallformers({ Component, pageProps }): AppProps {
  return (
    <>
      <Header />
      <Component {...pageProps} />
    </>
  )
}

export default Gallformers
