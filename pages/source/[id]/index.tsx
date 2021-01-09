import { GetStaticPaths, GetStaticProps } from 'next';
import { useRouter } from 'next/router';
import React from 'react';
import { Col, Row } from 'react-bootstrap';
import { SourceApi } from '../../../libs/api/apitypes';
import { allSourceIds, sourceById } from '../../../libs/db/source';
import { getStaticPathsFromIds, getStaticPropsWithContext } from '../../../libs/pages/nextPageHelpers';

type Props = {
    source: SourceApi;
};

const Source = ({ source }: Props): JSX.Element => {
    const router = useRouter();
    // If the page is not yet generated, this will be displayed initially until getStaticProps() finishes running
    if (router.isFallback) {
        return <div>Loading...</div>;
    }

    return (
        <div className="p-3 m-3">
            <Row className="pb-4">
                <Col>
                    <h2>{source.title}</h2>
                </Col>
            </Row>
            <Row className="pb-4">
                <Col>
                    <h5>Authors:</h5>
                    {source.author}
                </Col>
                <Col xs={3}>
                    <h5>Publication Year:</h5>
                    {source.pubyear}
                </Col>
            </Row>
            <Row className="pb-4">
                <Col>
                    <h5>Link:</h5>
                    <a href={source.link}>{source.link}</a>
                </Col>
            </Row>
            <Row className="pb-4">
                <Col>
                    <h5>Citation:</h5>
                    <i>{source.citation}</i>
                </Col>
            </Row>
        </div>
    );
};

// Use static so that this stuff can be built once on the server-side and then cached.
export const getStaticProps: GetStaticProps = async (context) => {
    const source = getStaticPropsWithContext(context, sourceById, 'source');

    return {
        props: {
            source: (await source)[0],
        },
        revalidate: 1,
    };
};

export const getStaticPaths: GetStaticPaths = async () => getStaticPathsFromIds(allSourceIds);

export default Source;
