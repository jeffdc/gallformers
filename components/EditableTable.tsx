import React, { useCallback, useState } from 'react';
import DataTable, { RowRecord, TableColumn, TableProps } from 'react-data-table-component';
import { WithID } from '../libs/utils/types';
import { hasProp } from '../libs/utils/util';

export type SelectEditorOptions = {
    value: string;
    label: string;
};

// Currently only support the default editor type (text input) or a select
export type EditableTableEditor = {
    type: 'select';
    options: SelectEditorOptions[];
};

export type EditableTableColumn<T> = Omit<TableColumn<T>, 'selector'> & {
    editable: boolean;
    // force it to a function which is the way the main library is headed anyhow
    selector: (t: T) => string;
    key: keyof T;
    editing?: boolean;
    editor?: EditableTableEditor;
};

type EditableCellProps<T extends WithID> = {
    row: T;
    index: number;
    column: EditableTableColumn<T>;
    editing: boolean;
    col: EditableTableColumn<T>;
    onChange: (field: keyof T, value: string) => void;
    onBlur: () => void;
    onClick: (row: T, col: EditableTableColumn<T>) => void;
};

export const EditableCell = <T extends WithID>({
    row,
    index,
    column,
    editing,
    col,
    onChange,
    onBlur,
    onClick,
}: EditableCellProps<T>): JSX.Element => {
    const [value, setValue] = useState(column.selector(row));
    if (editing) {
        switch (column?.editor?.type) {
            case 'select':
                return (
                    <select
                        autoFocus
                        data-tag="allowRowEvents"
                        className="form-control"
                        onChange={(e: React.ChangeEvent<HTMLSelectElement>) => {
                            const v = e.currentTarget.value;
                            console.log(`JDC: VV ${JSON.stringify(v, null, '  ')}`);
                            setValue(v);
                            onChange?.(column.key, v);
                        }}
                        onBlur={onBlur}
                        value={value}
                    >
                        {column.editor.options.map(({ value, label }) => (
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
                            onChange?.(column.key, e.target.value);
                        }}
                        onBlur={onBlur}
                        value={value}
                    />
                );
        }
    }

    if (col.cell) {
        return <div onClick={() => onClick(row, col)}>{col.cell(row, index, column, column.id ? column.id : -1)}</div>;
    }

    return (
        <div className="editable-table-cell" onClick={() => onClick(row, col)}>
            {column.selector(row)}
        </div>
    );
};

export type EditableTableProps<T extends RowRecord> = TableProps<T> & {
    columns: EditableTableColumn<T>[];
    data: T[];
    updateData: (t: T) => void;
};

const EditableTable = <T extends WithID>(props: EditableTableProps<T>): JSX.Element => {
    const [innerData, setInnerData] = useState(props.data);
    const [editData, setEditData] = useState<T>();
    const [editCell, setEditCell] = useState<[number, keyof T]>([-1, 'id']);

    const isEditing = (row: T, key: keyof T) => row.id === editCell[0] && key === editCell[1];

    const dataChange = (field: keyof T, value: string) => {
        if (!editData) {
            throw new Error(
                'editData is undefined after data changes. This is a sign of a programming error. Make sure to set the state based on the current row selection.',
            );
        }
        setEditData({ ...editData, [field]: value });
    };

    const edit = (row: T, col: EditableTableColumn<T>) => {
        setEditData(row);
        setEditCell([row.id, col.key]);
    };

    const save = () => {
        setInnerData(innerData.map((d) => (d.id === editData?.id ? editData : d)));
        setEditCell([-1, 'id']);
        if (editData) {
            props.updateData(editData);
        }
        setEditData(undefined);
    };

    const createCell = (row: T, index: number, column: EditableTableColumn<T>, col: EditableTableColumn<T>) => {
        const editing = isEditing(row, column.key);
        return (
            <EditableCell
                row={row}
                index={index}
                column={column}
                editing={editing}
                col={col}
                onChange={dataChange}
                onBlur={() => save()}
                onClick={() => edit(row, column)}
            />
        );
    };

    const mergedColumns = props.columns.map((col: EditableTableColumn<T>) => {
        if (!hasProp(col, 'editable') || !col.editable) {
            return col;
        }
        return {
            ...col,
            cell: createCell,
        };
    });

    const createColumns = useCallback(() => {
        return [...mergedColumns];
    }, [mergedColumns]);

    //TODO eliminate the cast
    return <DataTable {...props} columns={createColumns() as TableColumn<T>[]} data={props.data} />;
};

export default EditableTable;
