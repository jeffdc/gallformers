import { GetServerSideProps } from 'next';
import Head from 'next/head';
import React from 'react';
import Auth from '../../../components/auth';
import { hostById } from '../../../libs/db/host';
import { getFamiliesWithSpecies } from '../../../libs/db/taxonomy';
import { getStaticPropsWith, getStaticPropsWithContext } from '../../../libs/pages/nextPageHelpers';

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
                <p>Count: {data[0].galls.length}</p>
                <pre>{JSON.stringify(data, null, '  ')}</pre>
            </>
        </Auth>
    );
};

export const getServerSideProps: GetServerSideProps = async (context) => {
    const data = await getStaticPropsWithContext(context, hostById, 'TEST', true, true);
    // const data = await getStaticPropsWith(getFamiliesWithSpecies(true), 'gall families');
    // const data = await mightFail(() => O.none)(taxonomyTreeForId(55));
    return {
        props: {
            data: data,
        },
    };
};

export default Tester;
