import React, { useRef, useState } from 'react';
import { Button } from 'react-bootstrap';
import DataTable, { TableColumn, TableProps } from 'react-data-table-component';
import { WithID } from '../libs/utils/types';

export type SelectEditorOptions = {
    value: string;
    label: string;
};

// Currently only support the default editor type (text input) or a select. Would be nice to expand this and then move
// it into a new library as an add-on for the main ReactDataTable library.
export type EditableCellSelectEditor = {
    type: 'select';
    options: SelectEditorOptions[];
};

export type EditableTableColumn<T extends WithID> = TableColumn<T> & {
    editKey?: keyof T;
    editor?: EditableCellSelectEditor;
};

type EditableCellProps<T extends WithID> = {
    row: T;
    rowIndex: number;
    col: EditableTableColumn<T>;
    onChange: (row: T, field: keyof T, value: string) => void;
    columnKey: keyof T;
};

const getDataFromSelector = <T extends unknown>(row: T, rowIndex: number, col: TableColumn<T>): string => {
    if (!col.selector) {
        return '';
    } else if (typeof col.selector !== 'function') {
        // the ReactDataTable API allows the use of a string as the selector but has deprecated it. We will disallow it.
        throw new Error('selector must be a a function (e.g. row => row.field');
    } else {
        return col.selector(row, rowIndex) as string;
    }
};

/**
 * A basic EditableCell for a ReactDataTable. Assumptions are made around the type of the data in the cell,
 * namely that it is string data.
 */
const EditableCell = <T extends WithID>({ row, rowIndex, col, onChange, columnKey }: EditableCellProps<T>) => {
    const [value, setValue] = useState<string>(getDataFromSelector(row, rowIndex, col));
    const [editing, setEditing] = useState(false);

    const onBlur = () => {
        onChange(row, columnKey, value);
        setEditing(false);
    };

    if (editing) {
        switch (col.editor?.type) {
            case 'select':
                return (
                    <select
                        autoFocus
                        data-tag="allowRowEvents"
                        className="form-control"
                        onChange={(e: React.ChangeEvent<HTMLSelectElement>) => {
                            const v = e.currentTarget.value;
                            setValue(v);
                        }}
                        onBlur={onBlur}
                        value={value as string}
                    >
                        {col.editor.options.map(({ value, label }) => (
                            <option key={value} value={value}>
                                {label}
                            </option>
                        ))}
                    </select>
                );

            default:
                return (
                    <input
                        autoFocus
                        data-tag="allowRowEvents"
                        type={'text'}
                        className="form-control"
                        onChange={(e: React.ChangeEvent<HTMLInputElement>) => {
                            setValue(e.target.value);
                        }}
                        onBlur={onBlur}
                        value={value as string}
                    />
                );
        }
    }

    return (
        <div className="editable-table-cell" onClick={() => setEditing(true)}>
            {getDataFromSelector(row, rowIndex, col)}
        </div>
    );
};

export type EditableTableProps<T extends WithID> = Omit<TableProps<T>, 'columns'> & {
    createEmpty: () => T;
    columns: EditableTableColumn<T>[];
    update: (ts: T[]) => void;
};

const EditableTable = <T extends WithID>(props: EditableTableProps<T>): JSX.Element => {
    const [selected, setSelected] = useState(new Set<number>());
    const [toggleCleared, setToggleCleared] = useState(false);
    const newId = useRef(-1);

    const deleteSelected = () => {
        const d = props.data.filter((a) => !selected.has(a.id));
        setSelected(new Set());
        setToggleCleared(!toggleCleared);
        props.update(d);
    };

    const add = () => {
        const d = [...props.data];
        d.push({
            ...props.createEmpty(),
            id: newId.current,
        });
        newId.current = newId.current - 1;
        props.update(d);
    };

    const update = (m: T, field: keyof T, value: string) => {
        const editData = { ...m, [field]: value };
        const d = props.data.map((d) => (d.id === editData?.id ? editData : d));
        props.update(d);
    };

    const onSelectionChange = (selected: { allSelected: boolean; selectedCount: number; selectedRows: T[] }) => {
        const selection = new Set(selected.selectedRows.map((r) => r.id));
        setSelected(selection);
    };

    const contextActions = (
        <>
            <Button key="delete" variant="danger" className="btn-sm" onClick={deleteSelected}>
                Delete
            </Button>
        </>
    );

    const editCell = (row: T, rowIndex: number, column: EditableTableColumn<T>) => {
        if (!column.editKey) {
            throw new Error('Trying to make a cell editable that does not have an editKey.');
        }

        return <EditableCell row={row} col={column} rowIndex={rowIndex} onChange={update} columnKey={column.editKey} />;
    };

    const editableColumns = () => {
        return props.columns.map((col) => (col.editKey ? { ...col, cell: editCell } : col));
    };

    return (
        <DataTable
            {...props}
            columns={editableColumns()}
            data={props.data}
            selectableRows
            onSelectedRowsChange={onSelectionChange}
            clearSelectedRows={toggleCleared}
            actions={
                <Button onClick={add} variant="primary" className="btn-sm">
                    Add New
                </Button>
            }
            contextActions={contextActions}
        />
    );
};

export default EditableTable;
