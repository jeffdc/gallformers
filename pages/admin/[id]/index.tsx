import { GetServerSideProps } from 'next';
import Head from 'next/head.js';
import React from 'react';
import Auth from '../../../components/auth.js';
import { placeById } from '../../../libs/db/place.js';
import { getStaticPropsWithContext } from '../../../libs/pages/nextPageHelpers.js';

type Props = {
    data: unknown[];
};

const Tester = ({ data }: Props): JSX.Element => {
    return (
        <Auth superAdmin={true}>
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
    const data = await getStaticPropsWithContext(context, placeById, 'TEST', true, true);
    // const data = await getStaticPropsWith(getPlaces({ type: { in: ['state', 'province'] } }), 'TEST');
    // const data = await mightFail(() => O.none)(placeById(1));
    // const data = await mightFailWithArray<PlaceApi>()(getPlaces({ type: { in: ['state', 'province'] } }));
    // const data = await mightFailWithArray<GallIDApi>()(placeById(1));

    return {
        props: {
            data: data,
        },
    };
};

export default Tester;
