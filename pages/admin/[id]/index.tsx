import { GetServerSideProps } from 'next';
import Head from 'next/head';
import React from 'react';
import Auth from '../../../components/auth';
import { SimpleSpecies } from '../../../libs/api/apitypes';
import { getAllSpeciesForSection } from '../../../libs/db/taxonomy';
import { getStaticPropsWithContext } from '../../../libs/pages/nextPageHelpers';
import { mightFailWithArray } from '../../../libs/utils/util';

type Props = {
    data: any;
};

const Tester = ({ data }: Props): JSX.Element => {
    return (
        <Auth>
            <>
                <Head>
                    <title>Tester</title>
                </Head>
                <p>Count: {data.length}</p>
                <pre>{JSON.stringify(data, null, '  ')}</pre>
            </>
        </Auth>
    );
};

export const getServerSideProps: GetServerSideProps = async (context) => {
    // const data = await getStaticPropsWithContext(context, getAllSpeciesForSection, 'TEST');
    const data = await mightFailWithArray<SimpleSpecies>()(getAllSpeciesForSection(333));
    return {
        props: {
            data: data,
        },
    };
};

export default Tester;
