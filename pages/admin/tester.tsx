import { constant } from 'fp-ts/lib/function';
import { GetServerSideProps } from 'next';
import Head from 'next/head';
import React from 'react';
import { Button } from 'react-bootstrap';
import { useConfirmation } from '../../hooks/useconfirmation';
import { GallTaxon, HostTaxon } from '../../libs/api/apitypes';
import { EMPTY_FGS, TaxonomyEntry } from '../../libs/api/taxonomy';
import { hostsByGenus } from '../../libs/db/host';
import { sourcesBySpecies } from '../../libs/db/speciessource';
import { allGenera, allSections, taxonomyForSpecies } from '../../libs/db/taxonomy';
import { mightFail, mightFailWithArray } from '../../libs/utils/util';

type Props = {
    data: any;
};

const Tester = ({ data }: Props): JSX.Element => {
    const confirm = useConfirmation();

    const foo = () => {
        confirm({
            variant: 'danger',
            catchOnCancel: true,
            title: 'Are you sure want to create a new genus?',
            message: `Renaming the genus to will create a new genus under the current family. Do you want to continue?`,
        })
            .then(() => console.log('yes'))
            .catch(() => console.log('no'));
    };

    return (
        <>
            <Head>
                <title>Tester</title>
            </Head>
            <Button onClick={foo}>Click me</Button>
            <p>Count: {data.length}</p>
            <pre>{JSON.stringify(data, null, '  ')}</pre>
        </>
    );
};

export const getServerSideProps: GetServerSideProps = async () => {
    // const data = await mightFail(constant(EMPTY_FGS))(taxonomyForSpecies(690));
    const data = await mightFailWithArray()(sourcesBySpecies(587));
    return {
        props: {
            data: data,
        },
    };
};

export default Tester;
