import React, { useMemo, useState } from 'react';
import { Button } from 'react-bootstrap';
import DataTable from './DataTable';
import { AliasApi, COMMON_NAME, SCIENTIFIC_NAME } from '../libs/api/apitypes';
import { TABLE_CUSTOM_STYLES } from '../libs/utils/DataTableConstants';

export type SpeciesSynonymyProps = {
    aliases: AliasApi[];
    showAll: boolean;
};

const SpeciesSynonymy = ({ aliases, showAll }: SpeciesSynonymyProps): JSX.Element => {
    const juniorSynonyms = aliases.filter((a) => a.type === SCIENTIFIC_NAME);
    const [showJuniors, setShowJuniors] = useState(showAll);

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
                wrap: true,
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
                <strong>Synonymy: </strong>{' '}
                <span
                    style={{
                        display: 'block',
                        whiteSpace: 'nowrap',
                        overflow: 'hidden',
                        textOverflow: 'ellipsis',
                    }}
                    hidden={showAll}
                >
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
                            hidden={showAll}
                        >
                            {showJuniors ? <span>Hide</span> : <span>Click to see all synonym details.</span>}
                        </Button>
                        <div hidden={!showAll || !showJuniors}>
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
                                pagination={true}
                            />
                        </div>
                    </div>
                )}
            </span>
        </span>
    );
};

export default SpeciesSynonymy;
