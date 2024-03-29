import Link from 'next/link';
import React, { useMemo } from 'react';
import DataTable from './DataTable';
import { SimpleSpecies, TaxonCodeValues } from '../libs/api/apitypes';
import { TABLE_CUSTOM_STYLES } from '../libs/utils/DataTableConstants';

export type SourceListProps = {
    species: SimpleSpecies[];
};

const linkSpecies = (s: SimpleSpecies) => {
    const hostOrGall = s.taxoncode === TaxonCodeValues.GALL ? 'gall' : 'host';
    return (
        <Link key={s.id} href={`/${hostOrGall}/${s.id}`}>
            <i>{s.name}</i>
        </Link>
    );
};

const taxonDisplay = (s: SimpleSpecies) => {
    return s.taxoncode === TaxonCodeValues.GALL ? 'Gall Former' : 'Host';
};

const SpeciesTable = ({ species }: SourceListProps): JSX.Element => {
    const columns = useMemo(
        () => [
            {
                id: 'name',
                selector: (row: SimpleSpecies) => row.name,
                name: 'Name',
                sortable: true,
                format: linkSpecies,
            },
            {
                id: 'taxoncode',
                selector: (row: SimpleSpecies) => row.taxoncode,
                name: 'Taxon Type',
                sortable: true,
                format: taxonDisplay,
            },
        ],
        [],
    );

    return (
        <DataTable
            keyField={'id'}
            data={species}
            columns={columns}
            striped
            noHeader
            fixedHeader
            responsive={false}
            defaultSortFieldId="name"
            customStyles={TABLE_CUSTOM_STYLES}
        />
    );
};

export default SpeciesTable;
