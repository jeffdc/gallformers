import Head from 'next/head.js';
import Link from 'next/link.js';
import { Container, Col, Row } from 'react-bootstrap';

function Resources(): JSX.Element {
    return (
        <Container className="p-3 m-3">
            <Head.default>
                <meta name="description" content="Resources about plant galls" />
            </Head.default>
            <Row>
                <Col>
                    <h1>General Resources</h1>
                    <ul>
                        <li>
                            <Link.default href="/ref/IDGuide">Our guide to gall identification</Link.default>
                        </li>
                        <li>
                            <Link.default href="/filterguide">Detailed descriptions for our key filters</Link.default>
                        </li>
                        <li>
                            <Link.default href="/glossary">Glossary for plant and insect terms</Link.default>
                        </li>
                        <li>
                            <Link.default href="/refindex">Our reference library</Link.default>
                        </li>
                        <li>
                            <a href="https://www.inaturalist.org/posts/47564-tips-for-gall-hunting">Advice on finding galls</a>
                        </li>
                        <li>
                            <a href="https://www.inaturalist.org/journal/jeffdc/67593-getting-an-oak-identified">
                                Documenting Trees (Oak focused) for identification
                            </a>
                        </li>
                    </ul>
                </Col>
            </Row>
            <Row>
                <Col>
                    <h1>Books</h1>
                    <ul>
                        <li>
                            If you are new to galls <a href="http://charleyeiseman.com/">Charley Eiseman</a> and Noah
                            Charney&apos;s{' '}
                            <a href="https://bookshop.org/books/tracks-sign-of-insects-other-invertebrates-a-guide-to-north-american-species/9780811736244">
                                Tracks & Signs of Insects & Other Invertebrates: A Guide to North American Species
                            </a>{' '}
                            is a good place to start learning. It covers a lot more than just galls and is an excellent resource.
                        </li>
                        <li>
                            <a href="https://press.princeton.edu/books/paperback/9780691205762/plant-galls-of-the-western-united-states">
                                Russo&apos;s guide to galls of the Western US
                            </a>
                        </li>
                    </ul>
                </Col>
            </Row>
            <Row>
                <Col>
                    <h1>Non North American Resources</h1>
                    <ul>
                        <li>
                            To ID galls and other plant symptoms in Europe, visit{' '}
                            <a href="https://bladmineerders.nl/" target="_blank" rel="noreferrer">
                                bladmineerders.nl
                            </a>
                        </li>
                    </ul>
                </Col>
            </Row>
        </Container>
    );
}

export default Resources;
