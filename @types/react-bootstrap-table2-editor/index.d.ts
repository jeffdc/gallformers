/**
 * https://react-bootstrap-table.github.io/react-bootstrap-table2/docs/cell-edit-props.html
 */
declare module 'react-bootstrap-table2-editor' {
    export const TIME_TO_CLOSE_MESSAGE = 3000;
    export const DELAY_FOR_DBCLICK = 200;
    export const CLICK_TO_CELL_EDIT = 'click';
    export const DBCLICK_TO_CELL_EDIT = 'dbclick';

    export const TEXT = 'text';
    export const SELECT = 'select';
    export const TEXTAREA = 'textarea';
    export const CHECKBOX = 'checkbox';
    export const DATE = 'date';

    export const EDITTYPE = typeof TEXT | typeof SELECT | typeof TEXTAREA | typeof CHECKBOX | typeof DATE;
    export const Type = EDITTYPE;

    export type ColumnType = {
        dataField: string;
        test: string;
    };

    export interface CellEditFactoryProps<T> {
        mode: typeof CLICK_TO_CELL_EDIT | typeof DBCLICK_TO_CELL_EDIT;
        blurToSave?: boolean = false;
        nonEditableRows?: () => unknown[];
        timeToCloseMessage?: () => number = () => 3000;
        autoSelectText?: boolean = false;
        beforeSaveCell?: (oldValue: T, newValue: T, row: T, column: ColumnType) => unknown;
        afterSaveCell?: (oldValue: T, newValue: T, row: T, column: ColumnType) => unknown;
        onStartEdit?: (row: T, column: T, rowIndex: number, columnIndex: number) => unknown;
        errorMessage?: string;
        onErrorMessageDisappera?: () => unknown;
    }

    declare function cellEditFactory(props?: CellEditFactoryProps): unknown;
    export default cellEditFactory;
}
