import { GetStaticProps } from 'next';
import Head from 'next/head';
import React from 'react';
import { Col, Row } from 'react-bootstrap';
import { getCurrentStats, Stat } from '../libs/db/stats';
import { mightFailWithArray } from '../libs/utils/util';

type Props = {
    stats: Stat[];
};

const About = ({ stats }: Props): JSX.Element => {
    const statMap = new Map(stats.map((s) => [s.type, s.count] as [string, number]));
    return (
        <div className="p-5">
            <Head>
                <title>About Gallformers</title>
                <meta name="description" content="About the creators of gallformers and why we built the site." />
            </Head>

            <Row>
                <Col>
                    <h2>About Us</h2>
                </Col>
            </Row>
            <Row>
                <Col>
                    <p>
                        Gallformers is the product of curious amateurs becoming obsessed. If you are here then you too have at
                        least been touched, if not bitten, by the gall bug. It grows in you, but it is not a{' '}
                        <a href="./glossary#parasitism">parasite</a> nor an <a href="./glossary/#inquiline">inquiline</a>.
                    </p>
                    <p>
                        While you are here we hope that we can help you both ID an unknown plant gall as well as to learn about
                        galls. Whether your interests are very casual, you are a burgeoning scientist, or even a full-fledged{' '}
                        <a href="./glossary#cecidiology">cecidiologist</a> we strive to provide useful tools.
                    </p>
                    <p>
                        This site is open source and you can view the all of the code/data and if so inclined even open a pull
                        request on <a href="https://github.com/jeffdc/gallformers">GitHub</a>.
                    </p>
                    <p>
                        <h4>Current Site Stats:</h4>
                        There are currently
                        <ul>
                            <li>
                                {statMap.get('galls')} gallformers across {statMap.get('gall-family')} familes and{' '}
                                {statMap.get('gall-genera')} genera
                            </li>
                            <li>
                                {statMap.get('hosts')} hosts across {statMap.get('host-family')} familes and{' '}
                                {statMap.get('host-genera')} genera
                            </li>
                            <li>{statMap.get('sources')} sources</li>
                        </ul>
                    </p>
                </Col>
                <Col className="d-flex justify-content-center">
                    <img src="/images/gallmemaybe.jpg" alt="Gall Me Maybe" width={300} className="contain" />
                </Col>
            </Row>
            <Row className="mt-1 pt-1">
                <Col className="mt-5 pt-5 text-right">
                    <pre className="font-weight-light small text-muted">Build: {process.env.BUILD_ID}</pre>
                </Col>
            </Row>
        </div>
    );
};

export const getStaticProps: GetStaticProps = async () => {
    return {
        props: {
            stats: await mightFailWithArray<Stat>()(getCurrentStats()),
        },
        revalidate: 5 * 60, // every 5 minutes
    };
};

export default About;
