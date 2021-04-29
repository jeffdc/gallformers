import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/Option';
import { GetStaticProps } from 'next';
import Head from 'next/head';
import Link from 'next/link';
import React from 'react';
import { Card } from 'react-bootstrap';
import BootstrapTable, { ColumnDescription } from 'react-bootstrap-table-next';
import Edit from '../../../components/edit';
import { GallApi } from '../../../libs/api/apitypes';
import { allGalls } from '../../../libs/db/gall';
import { getStaticPropsWith } from '../../../libs/pages/nextPageHelpers';

type Props = {
    galls: GallApi[];
};

const linkHost = (cell: string, s: GallApi) => {
    return (
        <>
            <Link key={s.id} href={`/${s}/${s.id}`}>
                <a>{s.name}</a>
            </Link>
            <Edit id={s.id} type="source" />
        </>
    );
};

const formatAliases = (cell: string, h: GallApi) => <>{h.aliases.map((a) => a.name).join(', ')}</>;

const formatAbundance = (cell: string, h: GallApi) =>
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

const BrowseGalls = ({ galls }: Props): JSX.Element => {
    return (
        <>
            <Head>
                <title>Browse Galls</title>
            </Head>

            <Card>
                <Card.Body>
                    <Card.Title>Browse Galls</Card.Title>
                    <BootstrapTable
                        keyField={'id'}
                        data={galls}
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
            galls: await getStaticPropsWith(allGalls, 'galls'),
        },
        revalidate: 1,
    };
};

export default BrowseGalls;
