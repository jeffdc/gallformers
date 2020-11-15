import { source } from '@prisma/client';
import { GetStaticPaths, GetStaticProps } from 'next';
import React from 'react';
import { Col, Row } from 'react-bootstrap';
import { allSources, sourceById } from '../../../libs/db/source';
import { mightBeNull } from '../../../libs/db/utils';

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
    if (context === undefined || context.params === undefined || context.params.id === undefined) {
        throw new Error(`Source id can not be undefined.`);
    } else if (Array.isArray(context.params.id)) {
        throw new Error(`Expected single id but got an array of ids ${context.params.id}.`);
    }

    return {
        props: {
            source: await sourceById(parseInt(context.params.id)),
        },
        revalidate: 1,
    };
};

export const getStaticPaths: GetStaticPaths = async () => {
    const sources = await allSources();
    const paths = sources.map((source) => ({
        params: { id: source.id?.toString() },
    }));

    return { paths, fallback: false };
};

export default Source;
