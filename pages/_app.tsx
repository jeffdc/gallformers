import 'bootstrap/dist/css/bootstrap.min.css';
import { AppProps } from 'next/app';
import 'react-bootstrap-typeahead/css/Typeahead.css';
import Footer from './layouts/footer';
import Header from './layouts/header';

function Gallformers({ Component, pageProps }: AppProps): JSX.Element {
  // style stuff is to push the footer to the bottom when the page does not fill the screen
  return (
    <div style={ { display: 'flex', flexDirection: 'column', minHeight: '100vh' } }>
      <Header />
      <div style={{flex: 1}}>
        <Component {...pageProps} />
      </div>
      <Footer />
    </div>
  )
}

export default Gallformers
