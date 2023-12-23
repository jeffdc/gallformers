import { GetStaticPaths, GetStaticProps } from 'next';
import Head from 'next/head.js';
import { useRouter } from 'next/router.js';
import React from 'react';
import { Button, Col, Container, OverlayTrigger, Row, Tooltip } from 'react-bootstrap';
import Edit from '../../../components/edit.js';
import SpeciesTable from '../../../components/speciesTable.js';
import { SourceWithSpeciesApi } from '../../../libs/api/apitypes.js';
import { allSourceIds, sourceById } from '../../../libs/db/source.js';
import { getStaticPathsFromIds, getStaticPropsWithContext } from '../../../libs/pages/nextPageHelpers.js';

type Props = {
    source: SourceWithSpeciesApi;
};

const Source = ({ source }: Props): JSX.Element => {
    const router = useRouter();
    // If the page is not yet generated, this will be displayed initially until getStaticProps() finishes running
    if (router.isFallback) {
        return <div>Loading...</div>;
    }

    return (
        <Container className="pt-2" fluid>
            <Head.default>
                <title>{source.title}</title>
                <meta name="description" content={`${source.citation}`} />
            </Head.default>

            <Row className="pb-4">
                <Col>
                    <h2>{source.title}</h2>
                    <span>
                        <a href={source.link}>{source.link}</a>
                    </span>
                </Col>
                <Col xs={2}>
                    <span className="p-0 pe-1 my-auto">
                        <Edit id={source.id} type="source" />
                        <OverlayTrigger
                            placement="left"
                            overlay={
                                <Tooltip id="datacomplete">
                                    {source.datacomplete
                                        ? 'This source has been comprehensively reviewed and all relevant information entered.'
                                        : 'We are still working on this source so information from the source is potentially still missing.'}
                                </Tooltip>
                            }
                        >
                            <Button variant="outline-light">{source.datacomplete ? '💯' : '❓'}</Button>
                        </OverlayTrigger>
                    </span>
                </Col>
            </Row>
            <Row className="pb-1">
                <Col>
                    <strong>Authors:</strong> {source.author}
                </Col>
                <Col>
                    <strong>License:</strong>{' '}
                    {source.licenselink ? (
                        <a href={source.licenselink} target="_blank" rel="noreferrer">
                            {source.license}
                        </a>
                    ) : (
                        <span>{source.license}</span>
                    )}
                </Col>
            </Row>
            <Row className="pb-4">
                <Col>
                    <strong>Publication Year:</strong> {source.pubyear}
                </Col>
            </Row>
            <Row className="pb-4">
                <Col>
                    <strong>Citation (MLA Form):</strong> <i>{source.citation}</i>
                </Col>
            </Row>
            <Row>
                <Col>
                    <strong>Connected Species:</strong>
                    <SpeciesTable species={source.species} />
                </Col>
            </Row>
        </Container>
    );
};

// Use static so that this stuff can be built once on the server-side and then cached.
export const getStaticProps: GetStaticProps = async (context) => {
    try {
        const source = await getStaticPropsWithContext(context, sourceById, 'source');
        if (!source[0]) throw '404';

        return {
            props: {
                // must add a key so that a navigation from the same route will re-render properly
                key: source[0]?.id,
                source: source[0],
            },
            revalidate: 1,
        };
    } catch (e) {
        return { notFound: true };
    }
};

export const getStaticPaths: GetStaticPaths = async () => getStaticPathsFromIds(allSourceIds);

export default Source;
