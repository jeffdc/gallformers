import React, { useCallback, useRef, useState } from 'react';
import DataTable, { TableColumn, TableProps } from 'react-data-table-component';
import { WithID } from '../libs/utils/types';
import { hasProp } from '../libs/utils/util';

export type EditableTableColumn = TableColumn & {
    editable: boolean;
};

type EditableCellProps<T extends WithID> = {
    row: T;
    index: number;
    column: EditableTableColumn;
    col: unknown;
    onChange: (e: React.ChangeEvent<HTMLInputElement>) => void;
};

const EditableCell = <T extends WithID>({ row, index, column, col, onChange }: EditableCellProps<T>) => {
    const [value, setValue] = useState(row[column.selector]);

    const handleOnChange = (e: React.ChangeEvent<HTMLInputElement>) => {
        setValue(e.target.value);
        onChange?.(e);
    };

    if (column?.editing) {
        return (
            <input
                type={column.type || 'text'}
                name={column.selector}
                style={{ width: '100%' }}
                onChange={handleOnChange}
                value={value}
            />
        );
    }

    if (col.cell) {
        return col.cell(row, index, column);
    }
    return row[column.selector];
};

const EditableTable = <T extends WithID>(props: TableProps): JSX.Element => {
    const [innerData, setInnerData] = useState(props.data);
    const [editingId, setEditingId] = useState(-1);
    let formData = useRef({}).current;
    const isEditing = (record: T) => record.id === editingId;

    const formOnChange = (event: React.ChangeEvent<HTMLInputElement>) => {
        const nam = event.target.name;
        const val = event.target.value;

        formData = {
            ...formData,
            [nam]: val,
        };
    };

    const edit = (record: T) => {
        setEditingId(record.id);
    };

    const cancel = () => {
        setEditingId(-1);
    };

    const save = (item: T) => {
        const payload = { ...item, ...formData };
        const tempData = [...innerData];

        const index = tempData.findIndex((item) => editingId === item.id);
        if (index > -1) {
            const item = tempData[index];
            tempData.splice(index, 1, {
                ...item,
                ...payload,
            });
            setEditingId(-1);
            setInnerData(tempData);
        }
    };

    const mergedColumns = props.columns.map((col) => {
        if (!col.editable) {
            return col;
        }
        return {
            ...col,
            cell: (row, index, column) => {
                const editing = isEditing(row);
                return <EditableCell row={row} index={index} column={{ ...column, editing }} col={col} onChange={formOnChange} />;
            },
        };
    });

    const createColumns = useCallback(() => {
        return [
            ...mergedColumns,
            {
                name: 'Actions',
                allowOverflow: true,
                minWidth: '200px',
                cell: (row) => {
                    const editable = isEditing(row);
                    if (editable) {
                        return (
                            <div>
                                <button type="button" onClick={() => save(row)} style={{ backgroundColor: 'lightgreen' }}>
                                    save
                                </button>
                                <button type="button" onClick={cancel} style={{ backgroundColor: 'orangered' }}>
                                    cancel
                                </button>
                            </div>
                        );
                    }
                    return (
                        <button type="button" onClick={() => edit(row)} style={{ backgroundColor: 'aliceblue' }}>
                            edit
                        </button>
                    );
                },
            },
        ];
    }, [mergedColumns]);

    return <DataTable {...props} columns={createColumns()} data={innerData} />;
};

export default EditableTable;
