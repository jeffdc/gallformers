import Link from 'next/link.js';
import React, { useMemo } from 'react';
import DataTable from './DataTable.js';
import { SourceApi } from '../libs/api/apitypes.js';
import { TABLE_CUSTOM_STYLES } from '../libs/utils/DataTableConstants.js';
import Edit from './edit.js';

export type SourceTableProps = {
    sources: SourceApi[];
};
const MAX_TITLE_LEN = 150;
const linkSource = (s: SourceApi) => {
    return (
        <>
            <Link.default key={s.id} href={`/source/${s.id}`}>
                {s.title.length > MAX_TITLE_LEN ? `${s.title.substring(0, MAX_TITLE_LEN)}...` : s.title}
            </Link.default>
            <Edit id={s.id} type="source" />
        </>
    );
};

const SourceTable = ({ sources }: SourceTableProps): JSX.Element => {
    const columns = useMemo(
        () => [
            {
                id: 'title',
                selector: (row: SourceApi) => row.title,
                name: 'Name',
                sortable: true,
                format: linkSource,
                wrap: true,
                width: 'auto',
                grow: 3,
            },
            {
                id: 'author',
                selector: (row: SourceApi) => row.author,
                name: 'Author',
                maxWidth: '250px',
                sortable: true,
                grow: 2,
            },
            {
                id: 'pubyear',
                selector: (g: SourceApi) => g.pubyear,
                name: 'Year',
                sort: true,
                wrap: true,
                maxWidth: '100px',
            },
            {
                id: 'datacomplete',
                selector: (row: SourceApi) => row.datacomplete,
                name: 'Complete',
                sortable: true,
                wrap: true,
                format: (g: SourceApi) => (g.datacomplete ? 'YES' : 'NO'),
                maxWidth: '150px',
            },
            {
                id: 'license',
                selector: (g: SourceApi) => g.license,
                name: 'License',
                sort: true,
                maxWidth: '150px',
            },
        ],
        [],
    );

    return (
        <DataTable
            keyField={'id'}
            data={sources}
            columns={columns}
            striped
            noHeader
            fixedHeader
            responsive={false}
            defaultSortFieldId="title"
            customStyles={TABLE_CUSTOM_STYLES}
        />
    );
};

export default SourceTable;
