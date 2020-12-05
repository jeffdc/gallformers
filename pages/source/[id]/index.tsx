import { source } from '@prisma/client';
import { GetStaticPaths, GetStaticProps } from 'next';
import React from 'react';
import { Col, Row } from 'react-bootstrap';
import { allSourceIds, sourceById } from '../../../libs/db/source';
import { mightBeNull } from '../../../libs/db/utils';
import { getStaticPathsFromIds, getStaticPropsWithContext } from '../../../libs/pages/nextPageHelpers';

type Props = {
    source: source;
};

const Source = ({ source }: Props): JSX.Element => {
    return (
        <div className="p-3 m-3">
            <Row>
                <Col>
                    <h2>{source.title}</h2>
                </Col>
            </Row>
            <Row>
                <Col>
                    <h4>{source.author}</h4>
                </Col>
                <Col>
                    <b>{source.pubyear}</b>
                </Col>
            </Row>
            <Row>
                <Col>
                    <a href={mightBeNull(source.link)}>{source.link}</a>
                </Col>
            </Row>
            <Row>
                <Col>
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
