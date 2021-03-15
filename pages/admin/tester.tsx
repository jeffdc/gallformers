import { GetServerSideProps } from 'next';
import Head from 'next/head';
import React from 'react';
import { allGalls } from '../../libs/db/gall';
import { mightFailWithArray } from '../../libs/utils/util';

type Props = {
    data: any;
};

const Tester = ({ data }: Props): JSX.Element => {
    return (
        <>
            <Head>
                <title>Tester</title>
            </Head>
            <p>Count: {data.length}</p>
            <pre>{JSON.stringify(data, null, '  ')}</pre>
        </>
    );
};

export const getServerSideProps: GetServerSideProps = async () => {
    return {
        props: {
            data: await mightFailWithArray()(allGalls()),
        },
    };
};

export default Tester;
