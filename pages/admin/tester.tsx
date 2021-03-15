import { constant } from 'fp-ts/lib/function';
import { GetServerSideProps } from 'next';
import Head from 'next/head';
import React from 'react';
import { EMPTY_FGS } from '../../libs/api/taxonomy';
import { allGalls } from '../../libs/db/gall';
import { taxonomyForSpecies } from '../../libs/db/taxonomy';
import { mightFail, mightFailWithArray } from '../../libs/utils/util';

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
            data: await mightFail(constant(EMPTY_FGS))(taxonomyForSpecies(296)),
        },
    };
};

export default Tester;
