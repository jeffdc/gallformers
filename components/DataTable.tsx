/** A wrapper around react-datatable-component. Needed because the component has issues. */
import { default as ODataTable, TableProps } from 'react-data-table-component';
import useIsMounted from '../hooks/useIsMounted.js';

const DataTable = <T,>(props: TableProps<T>): JSX.Element => {
    const mounted = useIsMounted();

    return mounted ? <ODataTable.default {...props} /> : <b>Pending...</b>;
};

export default DataTable;
