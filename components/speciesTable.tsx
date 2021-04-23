import Link from 'next/link';
import React from 'react';
import BootstrapTable, { ColumnDescription } from 'react-bootstrap-table-next';
import { GallTaxon, SimpleSpecies } from '../libs/api/apitypes';

export type SourceListProps = {
    species: SimpleSpecies[];
};

const linkSpecies = (cell: string, s: SimpleSpecies) => {
    const hostOrGall = s.taxoncode === GallTaxon ? 'gall' : 'host';
    return (
        <Link key={s.id} href={`/${hostOrGall}/${s.id}`}>
            <a>{s.name}</a>
        </Link>
    );
};

const taxonDisplay = (cell: string, s: SimpleSpecies) => {
    return s.taxoncode === GallTaxon ? 'Gall Former' : 'Host';
};

const columns: ColumnDescription[] = [
    {
        dataField: 'name',
        text: 'Name',
        sort: true,
        formatter: linkSpecies,
    },
    {
        dataField: 'taxoncode',
        text: 'Taxon Type',
        sort: true,
        formatter: taxonDisplay,
    },
];

const SpeciesTable = ({ species }: SourceListProps): JSX.Element => {
    return (
        <BootstrapTable
            keyField={'id'}
            data={species}
            columns={columns}
            bootstrap4
            striped
            headerClasses="table-header"
            defaultSorted={[
                {
                    dataField: 'name',
                    order: 'asc',
                },
            ]}
        />
    );
};

export default SpeciesTable;
