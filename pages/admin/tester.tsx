import { GetServerSideProps } from 'next';
import Head from 'next/head';
import React from 'react';
import { gallById } from '../../libs/db/gall';
import { getAllSpeciesForFamily, getAllSpeciesForSection } from '../../libs/db/taxonomy';
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
            data: await mightFailWithArray()(getAllSpeciesForSection(304)),
        },
    };
};

export default Tester;
