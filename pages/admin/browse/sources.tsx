import { GetStaticProps } from 'next';
import Head from 'next/head.js';
import React from 'react';
import { Card } from 'react-bootstrap';
import SourceTable from '../../../components/sourceTable.js';
import { SourceWithSpeciesApi } from '../../../libs/api/apitypes.js';
import { allSourcesWithSpecies } from '../../../libs/db/source.js';
import { getStaticPropsWith } from '../../../libs/pages/nextPageHelpers.js';

type Props = {
    sources: SourceWithSpeciesApi[];
};

const BrowseSources = ({ sources }: Props): JSX.Element => {
    return (
        <>
            <Head.default>
                <title>Browse Sources</title>
            </Head.default>

            <Card>
                <Card.Body>
                    <Card.Title>Browse Sources</Card.Title>
                    <SourceTable sources={sources} />
                </Card.Body>
            </Card>
        </>
    );
};

// Use static so that this stuff can be built once on the server-side and then cached.
export const getStaticProps: GetStaticProps = async () => {
    return {
        props: {
            sources: await getStaticPropsWith(allSourcesWithSpecies, 'sources'),
        },
        revalidate: 1,
    };
};

export default BrowseSources;
