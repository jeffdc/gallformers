import React from 'react';
import { AliasApi, COMMON_NAME, EmptyAlias, SCIENTIFIC_NAME } from '../libs/api/apitypes';
import { TABLE_CUSTOM_STYLES } from '../libs/utils/DataTableConstants';
import EditableDataTable, { EditableTableColumn } from './EditableDataTable';

export type AliasTableProps = {
    data: AliasApi[];
    setData: (d: AliasApi[]) => void;
    disabled?: boolean;
};

const AliasTable = ({ data, setData, disabled }: AliasTableProps): JSX.Element => {
    const columns: EditableTableColumn<AliasApi>[] = [
        {
            name: 'Alias Name',
            selector: (row: AliasApi) => row.name,
            sortable: true,
            wrap: true,
            maxWidth: '300px',
            editKey: 'name',
        },
        {
            name: 'Type',
            selector: (row: AliasApi) => row.type,
            sortable: true,
            maxWidth: '150px',
            editKey: 'type',
            editor: {
                type: 'select',
                options: [
                    { value: COMMON_NAME, label: COMMON_NAME },
                    { value: SCIENTIFIC_NAME, label: SCIENTIFIC_NAME },
                ],
            },
        },
        {
            name: 'Description',
            selector: (row: AliasApi) => row.description,
            wrap: true,
            editKey: 'description',
        },
    ];

    return (
        <>
            Aliases:
            <EditableDataTable
                keyField={'id'}
                data={data}
                columns={columns}
                striped
                responsive={false}
                defaultSortFieldId="name"
                customStyles={TABLE_CUSTOM_STYLES}
                createEmpty={() => EmptyAlias}
                update={setData}
                disabled={disabled}
            />
            <p className="small">
                <em>
                    Changes to the aliases will not be saved until you save the whole form by clicking &lsquo;Save Changes&rsquo;
                    below.
                </em>
            </p>
        </>
    );
};

export default AliasTable;
