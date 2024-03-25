import { TableStyles } from 'react-data-table-component';

export const TABLE_CUSTOM_STYLES: TableStyles = {
    headRow: {
        style: {
            backgroundColor: '#96ADC8', //TODO how to get this from global scss styles?
        },
    },
    headCells: {
        style: {
            fontSize: '16px',
            paddingLeft: '12px',
            paddingRight: '4px',
        },
    },
    cells: {
        style: {
            fontSize: '16px',
            paddingLeft: '12px',
            paddingRight: '8px',
        },
    },
};

export const SELECTED_ROW_STYLE = {
    backgroundColor: '#F8F991',
};
