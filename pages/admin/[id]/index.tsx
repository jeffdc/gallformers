import { GetServerSideProps } from 'next';
import Head from 'next/head';
import React from 'react';
import Auth from '../../../components/auth';
import { getAllSpeciesForSection } from '../../../libs/db/taxonomy';
import { getStaticPropsWithContext } from '../../../libs/pages/nextPageHelpers';

type Props = {
    data: unknown[];
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
    const data = await getStaticPropsWithContext(context, getAllSpeciesForSection, 'TEST', true, true);
    // const data = await testTx();
    // const data = await mightFailWithArray()(getAllSpeciesForSection(317));
    return {
        props: {
            data: data,
        },
    };
};

export default Tester;
