import { GetServerSideProps } from 'next';
import Head from 'next/head';
import React from 'react';
import Auth from '../../../components/auth';
import { hostById } from '../../../libs/db/host';
import { getPlaces, placeById } from '../../../libs/db/place';
import { getFamiliesWithSpecies } from '../../../libs/db/taxonomy';
import { getStaticPropsWith, getStaticPropsWithContext } from '../../../libs/pages/nextPageHelpers';
import { mightFail, mightFailWithArray } from '../../../libs/utils/util';
import * as O from 'fp-ts/lib/Option';
import { GallIDApi, PlaceApi } from '../../../libs/api/apitypes';
import { gallsByHostGenus } from '../../../libs/db/gall';

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
