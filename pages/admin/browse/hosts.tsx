import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/Option';
import { GetStaticProps } from 'next';
import Head from 'next/head';
import Link from 'next/link';
import React from 'react';
import { Card } from 'react-bootstrap';
import BootstrapTable, { ColumnDescription } from 'react-bootstrap-table-next';
import Edit from '../../../components/edit';
import { HostApi } from '../../../libs/api/apitypes';
import { allHosts } from '../../../libs/db/host';
import { getStaticPropsWith } from '../../../libs/pages/nextPageHelpers';

type Props = {
    hosts: HostApi[];
};

const linkHost = (cell: string, s: HostApi) => {
    return (
        <>
            <Link key={s.id} href={`/${s}/${s.id}`}>
                <a>{s.name}</a>
            </Link>
            <Edit id={s.id} type="source" />
        </>
    );
};

const formatAliases = (cell: string, h: HostApi) => <>{h.aliases.map((a) => a.name).join(', ')}</>;

const formatAbundance = (cell: string, h: HostApi) =>
    pipe(
        h.abundance,
        O.fold(constant(''), (a) => a.abundance),
    );

const columns: ColumnDescription[] = [
    {
        dataField: 'name',
        text: 'Name',
        sort: true,
        width: 4,
        formatter: linkHost,
    },
    {
        dataField: 'datacomplete',
        text: 'Complete',
        sort: true,
    },
    {
        dataField: 'aliases',
        text: 'Aliases',
        sort: true,
        formatter: formatAliases,
    },
    {
        dataField: 'abundance',
        text: 'Abundance',
        sort: true,
        formatter: formatAbundance,
    },
];

const BrowseHosts = ({ hosts }: Props): JSX.Element => {
    return (
        <>
            <Head>
                <title>Browse Hosts</title>
            </Head>

            <Card>
                <Card.Body>
                    <Card.Title>Browse Hosts</Card.Title>
                    <BootstrapTable
                        keyField={'id'}
                        data={hosts}
                        columns={columns}
                        bootstrap4
                        striped
                        headerClasses="table-header"
                        defaultSorted={[
                            {
                                dataField: 'name',
                                order: 'asc',
                            },
                        ]}
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
