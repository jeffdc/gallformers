import Link from 'next/link';
import React, { useMemo } from 'react';
import DataTable from 'react-data-table-component';
import { GallTaxon, SimpleSpecies } from '../libs/api/apitypes';
import { TABLE_CUSTOM_STYLES } from '../libs/utils/DataTableConstants';

export type SourceListProps = {
    species: SimpleSpecies[];
};

const linkSpecies = (s: SimpleSpecies) => {
    const hostOrGall = s.taxoncode === GallTaxon ? 'gall' : 'host';
    return (
        <Link key={s.id} href={`/${hostOrGall}/${s.id}`}>
            <a>
                <i>{s.name}</i>
            </a>
        </Link>
    );
};

const taxonDisplay = (s: SimpleSpecies) => {
    return s.taxoncode === GallTaxon ? 'Gall Former' : 'Host';
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
