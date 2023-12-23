import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/Option';
import { GetStaticProps } from 'next';
import Head from 'next/head';
import Link from 'next/link';
import React, { useMemo } from 'react';
import { Card } from 'react-bootstrap';
import DataTable from '../../../components/DataTable';
import Edit from '../../../components/edit';
import { HostApi } from '../../../libs/api/apitypes';
import { allHosts } from '../../../libs/db/host';
import { getStaticPropsWith } from '../../../libs/pages/nextPageHelpers';
import { TABLE_CUSTOM_STYLES } from '../../../libs/utils/DataTableConstants';

type Props = {
    hosts: HostApi[];
};

const linkHost = (s: HostApi) => {
    return (
        <>
            <Link key={s.id} href={`/host/${s.id}`}>
                {s.name}
            </Link>
            <Edit id={s.id} type="host" />
        </>
    );
};

const BrowseHosts = ({ hosts }: Props): JSX.Element => {
    const columns = useMemo(
        () => [
            {
                id: 'name',
                selector: (row: HostApi) => row.name,
                name: 'Name',
                sortable: true,
                format: linkHost,
                maxWidth: '250px',
            },
            {
                id: 'datacomplete',
                selector: (row: HostApi) => row.datacomplete,
                name: 'Complete',
                sortable: true,
                wrap: true,
                format: (g: HostApi) => (g.datacomplete ? 'YES' : 'NO'),
                maxWidth: '150px',
            },
            {
                id: 'aliases',
                selector: (g: HostApi) => g.aliases.map((a) => a.name).join(', '),
                name: 'Aliases',
                sort: true,
                wrap: true,
            },
            {
                id: 'abundance',
                selector: (g: HostApi) =>
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
                <title>Browse Hosts</title>
            </Head>

            <Card>
                <Card.Body>
                    <Card.Title>Browse Hosts</Card.Title>
                    <DataTable
                        keyField={'id'}
                        data={hosts}
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
            hosts: await getStaticPropsWith(allHosts, 'hosts'),
        },
        revalidate: 1,
    };
};

export default BrowseHosts;
