import React from 'react';
import BootstrapTable, { ColumnDescription, SelectRowProps } from 'react-bootstrap-table-next';
import { SourceApi } from '../libs/api/apitypes';

export type SourceListProps = {
    data: SourceApi[];
    defaultSelection: SourceApi | undefined;
    onSelectionChange: (selected: SourceApi | undefined) => void;
};

const linkTitle = (cell: string, row: SourceApi) => {
    return (
        <span>
            <a href={`/source/${row.id}`}>{cell}</a>
        </span>
    );
};

const columns: ColumnDescription[] = [
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
        dataField: 'title',
        text: 'Title',
        sort: true,
        formatter: linkTitle,
    },
];

const SourceList = ({ data, defaultSelection, onSelectionChange }: SourceListProps): JSX.Element => {
    const selectRow: SelectRowProps<SourceApi> = {
        mode: 'radio',
        clickToSelect: true,
        onSelect: (row) => {
            onSelectionChange(row);
        },
        selected: defaultSelection != undefined ? [defaultSelection.id] : [],
    };

    return (
        <BootstrapTable
            keyField={'id'}
            data={data}
            columns={columns}
            bootstrap4
            striped
            headerClasses="table-header"
            selectRow={selectRow}
            defaultSorted={[
                {
                    dataField: 'year',
                    order: 'desc',
                },
            ]}
        />
    );
};

export default SourceList;
