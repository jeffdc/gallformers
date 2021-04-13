import { GetServerSideProps } from 'next';
import * as O from 'fp-ts/lib/Option';
import Head from 'next/head';
import React from 'react';
import Auth from '../../../components/auth';
import { allHosts } from '../../../libs/db/host';
import { allFamilyIds, getAllSpeciesForSection, taxonomyTreeForId } from '../../../libs/db/taxonomy';
import { getStaticPropsWithContext } from '../../../libs/pages/nextPageHelpers';
import { mightFail, mightFailWithArray } from '../../../libs/utils/util';

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
    const data = await getStaticPropsWithContext(context, allFamilyIds, 'TEST', true, true);
    // const data = await testTx();
    // const data = await mightFail(() => O.none)(taxonomyTreeForId(55));
    return {
        props: {
            data: data,
        },
    };
};

export default Tester;
