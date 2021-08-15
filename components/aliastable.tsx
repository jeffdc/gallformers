import React, { useCallback, useMemo, useState } from 'react';
import { Button } from 'react-bootstrap';
import { AliasApi, EmptyAlias } from '../libs/api/apitypes';
import { TABLE_CUSTOM_STYLES } from '../libs/utils/DataTableConstants';
import EditableTable, { EditableTableColumn } from './EditableTable';

export type AliasTableProps = {
    data: AliasApi[];
    setData: (d: AliasApi[]) => void;
};

const AliasTable = ({ data, setData }: AliasTableProps): JSX.Element => {
    const [selected, setSelected] = useState(new Set<number>());
    const [newId, setNewId] = useState(-1);
    const [toggleCleared, setToggleCleared] = useState(false);

    const columns: EditableTableColumn<AliasApi>[] = useMemo(
        () => [
            {
                id: 'name',
                selector: (row: AliasApi) => row.name,
                key: 'name',
                name: 'Alias Name',
                sortable: true,
                wrap: true,
                maxWidth: '300px',
                editable: true,
            },
            {
                id: 'type',
                selector: (row: AliasApi) => row.type,
                key: 'type',
                name: 'Type',
                sortable: true,
                maxWidth: '150px',
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
                key: 'description',
                name: 'Description',
                wrap: true,
                editable: true,
            },
        ],
        [],
    );

    const updateData = useCallback(
        (d: AliasApi[]) => {
            const dd = [...d];
            setData(dd);
        },
        [setData],
    );

    const updateAlias = useCallback(
        (updated: AliasApi) => {
            const d = data.map((orig) => (orig.id === updated.id ? updated : orig));
            updateData(d);
        },
        [data, updateData],
    );

    const addAlias = () => {
        data.push({
            ...EmptyAlias,
            id: newId,
        });
        updateData([...data]);
        setNewId(newId - 1);
    };

    const onSelectionChange = useCallback(
        (selected: { allSelected: boolean; selectedCount: number; selectedRows: AliasApi[] }) => {
            const selection = new Set(selected.selectedRows.map((r) => r.id));
            setSelected(selection);
        },
        [],
    );

    const contextActions = useMemo(() => {
        const handleDelete = () => {
            updateData(data.filter((a) => !selected.has(a.id)));
            setSelected(new Set());
            setToggleCleared(!toggleCleared);
        };

        return (
            <>
                <Button key="delete" onClick={handleDelete} variant="danger" className="btn-sm">
                    Delete
                </Button>
            </>
        );
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [selected]);

    return (
        <>
            <EditableTable
                keyField={'id'}
                data={data}
                columns={columns}
                striped
                responsive={false}
                defaultSortFieldId="name"
                customStyles={TABLE_CUSTOM_STYLES}
                selectableRows
                onSelectedRowsChange={onSelectionChange}
                clearSelectedRows={toggleCleared}
                actions={
                    <Button variant="secondary" className="btn-sm" onClick={addAlias}>
                        Add New Alias
                    </Button>
                }
                contextActions={contextActions}
                updateData={updateAlias}
            />
            <p className="font-italic small">
                Changes to the aliases will not be saved until you save the whole form by clicking &lsquo;Submit&rsquo; below.
            </p>
        </>
    );
};

export default AliasTable;
