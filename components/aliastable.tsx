import React, { useState } from 'react';
import { Button } from 'react-bootstrap';
import BootstrapTable, { ColumnDescription, SelectRowProps } from 'react-bootstrap-table-next';
import cellEditFactory, { CellEditFactoryProps } from 'react-bootstrap-table2-editor';
import { AliasApi, EmptyAlias } from '../libs/api/apitypes';

export type AliasTableProps = {
    data: AliasApi[];
    setData: (d: AliasApi[]) => void;
};

const aliasColumns: ColumnDescription[] = [
    { dataField: 'name', text: 'Alias Name' },
    {
        dataField: 'type',
        text: 'Alias Type',
        editor: {
            type: 'select',
            options: [
                { value: 'common', label: 'common' },
                { value: 'scientific', label: 'scientific' },
            ],
        },
    },
    { dataField: 'description', text: 'Alias Description' },
];

const cellEditProps: CellEditFactoryProps<AliasApi> = {
    mode: 'click',
    blurToSave: true,
};

const AliasTable = ({ data, setData }: AliasTableProps): JSX.Element => {
    const [selected, setSelected] = useState(new Set<number>());

    const addAlias = () => {
        data.push(EmptyAlias);
        setData([...data]);
    };

    const deleteAliases = () => {
        setData(data.filter((a) => !selected.has(a.id)));
        setSelected(new Set());
    };

    const selectRow: SelectRowProps<AliasApi> = {
        mode: 'checkbox',
        clickToSelect: false,
        clickToEdit: true,
        onSelect: (row) => {
            const selection = new Set(selected);
            selection.has(row.id) ? selection.delete(row.id) : selection.add(row.id);
            setSelected(selection);
        },
        onSelectAll: (isSelect) => {
            if (isSelect) {
                setSelected(new Set(data.map((a) => a.id)));
            } else {
                setSelected(new Set());
            }
        },
    };

    return (
        <>
            <BootstrapTable
                keyField={'id'}
                data={data}
                columns={aliasColumns}
                bootstrap4
                striped
                headerClasses="table-header"
                cellEdit={cellEditFactory(cellEditProps)}
                selectRow={selectRow}
            />
            <Button variant="secondary" className="btn-sm mr-2" onClick={addAlias}>
                Add Alias
            </Button>
            <Button variant="secondary" className="btn-sm" disabled={selected.size == 0} onClick={deleteAliases}>
                Delete Selected Alias(es)
            </Button>
            <p className="font-italic small">
                Changes to the aliases will not be saved until you save the whole form by clicking &lsquo;Submit&rsquo; below.
            </p>
        </>
    );
};

export default AliasTable;
