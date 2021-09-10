import React, { useCallback, useMemo, useState } from 'react';
import { Alert, Button } from 'react-bootstrap';
import DataTable from 'react-data-table-component';
import { ALLRIGHTS, CC0, CCBY, SourceApi, SpeciesSourceApi } from '../libs/api/apitypes';
import { SELECTED_ROW_STYLE, TABLE_CUSTOM_STYLES } from '../libs/utils/DataTableConstants';

export type SourceListProps = {
    data: SpeciesSourceApi[];
    defaultSelection: SourceApi | undefined;
    onSelectionChange: (selected: SourceApi | undefined) => void;
};

const linkTitle = (row: SourceApi) => {
    return (
        <span>
            <a href={`/source/${row.id}`}>{row.title}</a>
        </span>
    );
};

const linkLicense = (row: SourceApi) => {
    const link = row.licenselink ? row.licenselink : 'https://creativecommons.org/publicdomain/mark/1.0/';
    return (
        <span>
            <a href={link} target="_blank" rel="noreferrer">
                <img
                    alt={link}
                    src={
                        row.license === CC0
                            ? '/images/CC0.png'
                            : row.license === CCBY
                            ? '/images/CCBY.png'
                            : row.license === ALLRIGHTS
                            ? '/images/allrights.svg'
                            : ''
                    }
                    height="20"
                />
            </a>
        </span>
    );
};

const SourceList = ({ data, defaultSelection, onSelectionChange }: SourceListProps): JSX.Element => {
    const [selectedId, setSelectedId] = useState(defaultSelection?.id);
    const [notesAlertShown, setNotesAlertShown] = useState(true);

    const gallformersNotes = data.find((s) => s.source?.id === 58)?.source;

    const columns = useMemo(
        () => [
            {
                id: 'author',
                selector: (row: SourceApi) => row.author,
                name: 'Author(s)',
                sortable: true,
                wrap: true,
                maxWidth: '200px',
            },
            {
                id: 'pubyear',
                selector: (row: SourceApi) => row.pubyear,
                name: 'Year',
                sortable: true,
                maxWidth: '50px',
                center: true,
                hide: 599,
            },
            {
                id: 'title',
                selector: (row: SourceApi) => row.title,
                name: 'Title',
                sortable: true,
                format: linkTitle,
                wrap: true,
                maxWidth: '500px',
            },
            {
                id: 'license',
                selector: (row: SourceApi) => row.license,
                name: 'License',
                sortable: true,
                format: linkLicense,
                maxWidth: '50px',
                center: true,
                hide: 599,
            },
        ],
        [],
    );

    const selectRow = useCallback(
        (row?: SourceApi) => {
            setSelectedId(row?.id);
            onSelectionChange(row);
        },
        [onSelectionChange],
    );

    const condRowStyles = useMemo(
        () => [
            {
                when: (row: SourceApi) => row.id == selectedId,
                style: () => SELECTED_ROW_STYLE,
            },
        ],
        [selectedId],
    );

    return (
        <>
            <Alert
                variant="info"
                dismissible
                onClose={() => setNotesAlertShown(false)}
                hidden={!notesAlertShown || !(gallformersNotes && gallformersNotes.id !== selectedId)}
            >
                Our ID Notes may contain important tips necessary for distinguishing this gall from similar galls and/or important
                information about the taxonomic status of this gall inducer.
                <Button className="ml-3" variant="outline-info" size="sm" onClick={() => selectRow(gallformersNotes)}>
                    Show notes
                </Button>
            </Alert>

            <DataTable
                keyField={'id'}
                data={data.map((s) => s.source)}
                columns={columns}
                striped
                dense
                noHeader
                responsive={false}
                defaultSortFieldId="pubyear"
                customStyles={TABLE_CUSTOM_STYLES}
                onRowClicked={selectRow}
                conditionalRowStyles={condRowStyles}
            />
        </>
    );
};

export default SourceList;
