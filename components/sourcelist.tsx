import React, { useCallback, useMemo, useState } from 'react';
import { Alert, Button, Col, Row } from 'react-bootstrap';
import ReactMarkdown from 'react-markdown';
import rehypeRaw from 'rehype-raw';
import remarkBreaks from 'remark-breaks';
import rehypeExternalLinks from 'rehype-external-links';
import { ALLRIGHTS, CC0, CCBY, GallTaxon, HostTaxon, SpeciesSourceApi } from '../libs/api/apitypes';
import { formatLicense, sourceToDisplay } from '../libs/pages/renderhelpers';
import { SELECTED_ROW_STYLE, TABLE_CUSTOM_STYLES } from '../libs/utils/DataTableConstants';
import DataTable from './DataTable';
import Edit from './edit';
import InfoTip from './infotip';

export type SourceListProps = {
    data: SpeciesSourceApi[];
    defaultSelection: SpeciesSourceApi | undefined;
    onSelectionChange: (selected: SpeciesSourceApi | undefined) => void;
    taxonType: typeof GallTaxon | typeof HostTaxon;
};

const linkTitle = (row: SpeciesSourceApi) => {
    return (
        <span>
            <a href={`/source/${row.source.id}`}>{row.source.title}</a>
        </span>
    );
};

const linkLicense = (row: SpeciesSourceApi) => {
    const link = row.source.licenselink ? row.source.licenselink : 'https://creativecommons.org/publicdomain/mark/1.0/';
    return (
        <span>
            <a href={link} target="_blank" rel="noreferrer">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                    alt={link}
                    src={
                        row.source.license === CC0
                            ? '/images/CC0.png'
                            : row.source.license === CCBY
                              ? '/images/CCBY.png'
                              : row.source.license === ALLRIGHTS
                                ? '/images/allrights.svg'
                                : ''
                    }
                    height="20"
                />
            </a>
        </span>
    );
};

const SourceList = ({ data, defaultSelection, onSelectionChange, taxonType }: SourceListProps): JSX.Element => {
    const [selectedSource, setSelectedSource] = useState(defaultSelection);
    const [notesAlertShown, setNotesAlertShown] = useState(true);
    const sources = data.sort((a, b) => parseInt(a.source.pubyear) - parseInt(b.source.pubyear));

    const gallformersNotes = data.find((s) => s.source?.id === 58);

    const columns = useMemo(
        () => [
            {
                id: 'author',
                selector: (row: SpeciesSourceApi) => row.source.author,
                name: 'Author(s)',
                sortable: true,
                wrap: true,
                maxWidth: '200px',
            },
            {
                id: 'pubyear',
                selector: (row: SpeciesSourceApi) => row.source.pubyear,
                name: 'Year',
                sortable: true,
                maxWidth: '50px',
                center: true,
                hide: 599,
            },
            {
                id: 'title',
                selector: (row: SpeciesSourceApi) => row.source.title,
                name: 'Title',
                sortable: true,
                format: linkTitle,
                wrap: true,
                maxWidth: '500px',
            },
            {
                id: 'license',
                selector: (row: SpeciesSourceApi) => row.source.license,
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
        (row?: SpeciesSourceApi) => {
            setSelectedSource(row);
            onSelectionChange(row);
        },
        [onSelectionChange],
    );

    const condRowStyles = useMemo(
        () => [
            {
                when: (row: SpeciesSourceApi) => row.source.id == selectedSource?.source.id,
                style: () => SELECTED_ROW_STYLE,
            },
        ],
        [selectedSource],
    );

    const changeSource = (num: number) => () => {
        const currIdx = sources.findIndex((s) => s.source.id === selectedSource?.source.id);
        const newIdx = (currIdx + num + sources.length) % sources.length;
        selectRow(sources[newIdx]);
    };

    return (
        <>
            <Alert
                variant="info"
                dismissible
                onClose={() => setNotesAlertShown(false)}
                hidden={
                    taxonType === HostTaxon ||
                    !notesAlertShown ||
                    !(gallformersNotes && gallformersNotes.id !== selectedSource?.source.id)
                }
            >
                Our ID Notes may contain important tips necessary for distinguishing this gall from similar galls and/or important
                information about the taxonomic status of this gall inducer.
                <Button className="ms-3" variant="outline-info" size="sm" onClick={() => selectRow(gallformersNotes)}>
                    Show notes
                </Button>
            </Alert>
            <Row>
                <Col sm={10} xs={12}>
                    <div>
                        <em>
                            {selectedSource?.source.title}
                            {selectedSource && <Edit id={selectedSource?.source.id} type="source" />}
                        </em>
                    </div>
                </Col>
                <Col className="d-flex justify-content-end">
                    <Button
                        variant="secondary"
                        size="sm"
                        onClick={changeSource(-1)}
                        disabled={data.length <= 1}
                        className="me-1"
                        aria-label="select previous source"
                    >
                        {'<'}
                    </Button>
                    <Button
                        variant="secondary"
                        size="sm"
                        onClick={changeSource(1)}
                        disabled={data.length <= 1}
                        aria-label="select next source"
                    >
                        {'>'}
                    </Button>
                </Col>
            </Row>
            <Row>
                <Col id="description" className="lead p-3">
                    {selectedSource && selectedSource.description && (
                        <span>
                            <span className="source-quotemark">&ldquo;</span>
                            <ReactMarkdown rehypePlugins={[rehypeRaw]} remarkPlugins={[rehypeExternalLinks, remarkBreaks]}>
                                {selectedSource.description}
                            </ReactMarkdown>
                            <span className="source-quotemark">&rdquo;</span>
                            <p>
                                <i>- {sourceToDisplay(selectedSource.source)}</i>
                                <InfoTip
                                    id="copyright"
                                    text={`Source entries are edited for relevance, brevity, and formatting. All text is quoted from the selected source except where noted by [brackets].\nThis source: ${formatLicense(
                                        selectedSource.source,
                                    )}.`}
                                    tip="©"
                                />
                            </p>
                            <p className="description-text">
                                {selectedSource.externallink && (
                                    <span>
                                        Reference:{' '}
                                        <a href={selectedSource.externallink} target="_blank" rel="noreferrer">
                                            {selectedSource.externallink}
                                        </a>
                                    </span>
                                )}
                            </p>
                        </span>
                    )}
                </Col>
            </Row>
            <Row>
                <Col>
                    <hr />
                </Col>
            </Row>
            <Row>
                <Col>
                    {selectedSource && <Edit id={selectedSource?.species_id} type="speciessource" />}
                    <strong>Further Information:</strong>
                </Col>
            </Row>
            <Row>
                <Col>
                    <DataTable
                        keyField={'id'}
                        data={data}
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
                </Col>
            </Row>
        </>
    );
};

export default SourceList;
