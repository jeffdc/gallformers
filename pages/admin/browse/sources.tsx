import { GetStaticProps } from 'next';
import Head from 'next/head';
import React from 'react';
import { Card } from 'react-bootstrap';
import SourceTable from '../../../components/sourceTable';
import { SourceWithSpeciesApi } from '../../../libs/api/apitypes';
import { allSourcesWithSpecies } from '../../../libs/db/source';
import { getStaticPropsWith } from '../../../libs/pages/nextPageHelpers';

type Props = {
    sources: SourceWithSpeciesApi[];
};

const BrowseSources = ({ sources }: Props): JSX.Element => {
    return (
        <>
            <Head>
                <title>Browse Sources</title>
            </Head>

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
