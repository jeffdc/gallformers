import Link from 'next/link';
import React from 'react';
import BootstrapTable, { ColumnDescription } from 'react-bootstrap-table-next';
import { SourceApi } from '../libs/api/apitypes';
import Edit from './edit';

export type SourceTableProps = {
    sources: SourceApi[];
};

const linkSource = (cell: string, s: SourceApi) => {
    return (
        <>
            <Link key={s.id} href={`/source/${s.id}`}>
                <a>{s.title}</a>
            </Link>
            <Edit id={s.id} type="source" />
        </>
    );
};

const columns: ColumnDescription[] = [
    {
        dataField: 'title',
        text: 'Title',
        sort: true,
        formatter: linkSource,
    },
    {
        dataField: 'author',
        text: 'Author',
        sort: true,
    },
    {
        dataField: 'pubyear',
        text: 'Year',
        sort: true,
    },
    {
        dataField: 'datacomplete',
        text: 'Complete',
        sort: true,
    },
    {
        dataField: 'license',
        text: 'License',
        sort: true,
    },
];

const SourceTable = ({ sources }: SourceTableProps): JSX.Element => {
    return (
        <BootstrapTable
            keyField={'id'}
            data={sources}
            columns={columns}
            bootstrap4
            striped
            headerClasses="table-header"
            defaultSorted={[
                {
                    dataField: 'title',
                    order: 'asc',
                },
            ]}
        />
    );
};

export default SourceTable;
