import React, { useMemo, useState } from 'react';
import { Button } from 'react-bootstrap';
import DataTable from 'react-data-table-component';
import { AliasApi, EmptyAlias } from '../libs/api/apitypes';
import { TABLE_CUSTOM_STYLES } from '../libs/utils/DataTableConstants';

export type AliasTableProps = {
    data: AliasApi[];
    setData: (d: AliasApi[]) => void;
};

const AliasTable = ({ data, setData }: AliasTableProps): JSX.Element => {
    const [selected, setSelected] = useState(new Set<number>());
    const [newId, setNewId] = useState(-1);

    const columns = useMemo(
        () => [
            {
                id: 'name',
                selector: (row: AliasApi) => row.name,
                name: 'Alias Name',
                sortable: true,
                wrap: true,
                maxWidth: '300px',
                editable: true,
            },
            {
                id: 'type',
                selector: (row: AliasApi) => row.type,
                name: 'Type',
                sortable: true,
                maxWidth: '100px',
                editable: true,
                editor: {
                    type: 'select',
                    options: [
                        { value: 'common', label: 'common' },
                        { value: 'scientific', label: 'scientific' },
                    ],
                },
            },
            {
                id: 'description',
                selector: (row: AliasApi) => row.description,
                name: 'Description',
                wrap: true,
                editable: true,
            },
        ],
        [],
    );

    const addAlias = () => {
        data.push({
            ...EmptyAlias,
            id: newId,
        });
        setNewId(newId - 1);
        setData([...data]);
    };

    const deleteAliases = () => {
        setData(data.filter((a) => !selected.has(a.id)));
        setSelected(new Set());
    };

    // const selectRow: SelectRowProps<AliasApi> = {
    //     mode: 'checkbox',
    //     clickToSelect: false,
    //     clickToEdit: true,
    //     onSelect: (row) => {
    //         const selection = new Set(selected);
    //         selection.has(row.id) ? selection.delete(row.id) : selection.add(row.id);
    //         setSelected(selection);
    //     },
    //     onSelectAll: (isSelect) => {
    //         if (isSelect) {
    //             setSelected(new Set(data.map((a) => a.id)));
    //         } else {
    //             setSelected(new Set());
    //         }
    //     },
    // };

    const onSelectionChange = (selected: { allSelected: boolean; selectedCount: number; selectedRows: AliasApi[] }) => {
        const selection = new Set(selected.selectedRows.map((r) => r.id));
        setSelected(selection);
    };

    return (
        <>
            <DataTable
                keyField={'id'}
                data={data}
                columns={columns}
                striped
                noHeader
                responsive={false}
                defaultSortFieldId="name"
                customStyles={TABLE_CUSTOM_STYLES}
                selectableRows
                onSelectedRowsChange={onSelectionChange}
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
