import React, { useMemo, useState } from 'react';
import { Button } from 'react-bootstrap';
import DataTable from 'react-data-table-component';
import { AliasApi, COMMON_NAME, SCIENTIFIC_NAME } from '../libs/api/apitypes';
import { TABLE_CUSTOM_STYLES } from '../libs/utils/DataTableConstants';

export type SpeciesSynonymyProps = {
    aliases: AliasApi[];
};

const SpeciesSynonymy = ({ aliases }: SpeciesSynonymyProps): JSX.Element => {
    const juniorSynonyms = aliases.filter((a) => a.type === SCIENTIFIC_NAME);
    const [showJuniors, setShowJuniors] = useState(false);

    const columns = useMemo(
        () => [
            {
                id: 'name',
                selector: (row: AliasApi) => row.name,
                name: 'Name',
                sortable: true,
            },
            {
                id: 'notes',
                selector: (row: AliasApi) => row.description,
                name: 'Notes',
            },
        ],
        [],
    );

    return (
        <span>
            <div>
                <strong>Common Name(s): </strong>
                <span>
                    {aliases
                        .filter((a) => a.type === COMMON_NAME)
                        .map((a) => a.name)
                        .sort()
                        .join(', ')}
                </span>
            </div>
            <span>
                <span
                    style={{
                        display: 'block',
                        whiteSpace: 'nowrap',
                        overflow: 'hidden',
                        textOverflow: 'ellipsis',
                    }}
                >
                    <strong>Synoynmy: </strong>{' '}
                    {juniorSynonyms
                        .map((s) => s.name)
                        .sort()
                        .join(', ')}
                </span>
                {juniorSynonyms.length > 0 && (
                    <div>
                        <Button
                            variant="outline-secondary"
                            size="sm"
                            className="mb-1"
                            onClick={() => setShowJuniors(!showJuniors)}
                        >
                            {showJuniors ? <span>Hide</span> : <span>Click to see all synonym details.</span>}
                        </Button>
                        <div hidden={!showJuniors}>
                            <DataTable
                                keyField={'id'}
                                data={juniorSynonyms}
                                columns={columns}
                                striped
                                noHeader
                                dense
                                fixedHeader
                                responsive={false}
                                defaultSortFieldId="name"
                                customStyles={TABLE_CUSTOM_STYLES}
                            />
                        </div>
                    </div>
                )}
            </span>
        </span>
    );
};

export default SpeciesSynonymy;
