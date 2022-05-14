import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/Option';
import { GetStaticProps } from 'next';
import Head from 'next/head';
import Link from 'next/link';
import React, { useMemo } from 'react';
import { Card } from 'react-bootstrap';
import DataTable from '../../../components/DataTable';
import Edit from '../../../components/edit';
import { GallApi } from '../../../libs/api/apitypes';
import { allGalls } from '../../../libs/db/gall';
import { getStaticPropsWith } from '../../../libs/pages/nextPageHelpers';
import { TABLE_CUSTOM_STYLES } from '../../../libs/utils/DataTableConstants';

type Props = {
    galls: GallApi[];
};

const linkGall = (s: GallApi) => {
    return (
        <>
            <Link key={s.id} href={`/gall/${s.id}`}>
                <a>{s.name}</a>
            </Link>
            <Edit id={s.id} type="gall" />
        </>
    );
};

const BrowseGalls = ({ galls }: Props): JSX.Element => {
    const columns = useMemo(
        () => [
            {
                id: 'name',
                selector: (row: GallApi) => row.name,
                name: 'Name',
                sortable: true,
                format: linkGall,
                maxWidth: '250px',
            },
            {
                id: 'datacomplete',
                selector: (row: GallApi) => row.datacomplete,
                name: 'Complete',
                sortable: true,
                wrap: true,
                format: (g: GallApi) => (g.datacomplete ? 'YES' : 'NO'),
                maxWidth: '150px',
            },
            {
                id: 'aliases',
                selector: (g: GallApi) => g.aliases.map((a) => a.name).join(', '),
                name: 'Aliases',
                sort: true,
                wrap: true,
            },
            {
                id: 'abundance',
                selector: (g: GallApi) =>
                    pipe(
                        g.abundance,
                        O.fold(constant(''), (a) => a.abundance),
                    ),
                name: 'Abundance',
                sort: true,
                maxWidth: '150px',
            },
        ],
        [],
    );

    return (
        <>
            <Head>
                <title>Browse Galls</title>
            </Head>

            <Card>
                <Card.Body>
                    <Card.Title>Browse Galls</Card.Title>
                    <DataTable
                        keyField={'id'}
                        data={galls}
                        columns={columns}
                        striped
                        noHeader
                        fixedHeader
                        responsive={false}
                        defaultSortFieldId="name"
                        customStyles={TABLE_CUSTOM_STYLES}
                    />
                </Card.Body>
            </Card>
        </>
    );
};

// Use static so that this stuff can be built once on the server-side and then cached.
export const getStaticProps: GetStaticProps = async () => {
    return {
        props: {
            galls: await getStaticPropsWith(allGalls, 'galls'),
        },
        revalidate: 1,
    };
};

export default BrowseGalls;
