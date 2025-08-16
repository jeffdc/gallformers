import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/Option';
import { GetStaticProps } from 'next';
import Head from 'next/head';
import Link from 'next/link';
import React, { useMemo, useState } from 'react';
import { Card, Form } from 'react-bootstrap';
import DataTable from '../../../components/DataTable';
import Edit from '../../../components/edit';
import { GallApi } from '../../../libs/api/apitypes';
import { allGalls } from '../../../libs/db/gall';
import { getStaticPropsWith } from '../../../libs/pages/nextPageHelpers';
import { TABLE_CUSTOM_STYLES } from '../../../libs/utils/DataTableConstants';

type Props = {
    galls: GallApi[];
};

const linkGall = (s: GallApi) => {
    return (
        <>
            <Link key={s.id} href={`/gall/${s.id}`}>
                {s.name}
            </Link>
            <Edit id={s.id} type="gall" />
        </>
    );
};

const BrowseGalls = ({ galls }: Props): JSX.Element => {
    const [filterText, setFilterText] = useState('');
    const [filteredItems, setFilteredItems] = useState(galls);

    const handleFilterChange = (e: React.ChangeEvent<HTMLInputElement>) => {
        const value = e.target.value;
        setFilterText(value);

        if (!value) {
            setFilteredItems(galls);
            return;
        }

        const filtered = galls.filter((item) => {
            const searchValue = value.toLowerCase();
            const nameMatch = item.name.toLowerCase().includes(searchValue);
            const aliasMatch = item.aliases.some((alias) => alias.name.toLowerCase().includes(searchValue));
            const abundanceMatch = pipe(
                item.abundance,
                O.fold(
                    () => false,
                    (abundance) => abundance.abundance.toLowerCase().includes(searchValue),
                ),
            );

            return nameMatch || aliasMatch || abundanceMatch;
        });

        setFilteredItems(filtered);
    };

    const columns = useMemo(
        () => [
            {
                id: 'name',
                selector: (row: GallApi) => row.name,
                name: 'Name',
                sortable: true,
                format: linkGall,
                maxWidth: '250px',
            },
            {
                id: 'datacomplete',
                selector: (row: GallApi) => row.datacomplete,
                name: 'Complete',
                sortable: true,
                wrap: true,
                format: (g: GallApi) => (g.datacomplete ? 'YES' : 'NO'),
                maxWidth: '150px',
            },
            {
                id: 'aliases',
                selector: (g: GallApi) => g.aliases.map((a) => a.name).join(', '),
                name: 'Aliases',
                sort: true,
                wrap: true,
            },
            {
                id: 'abundance',
                selector: (g: GallApi) =>
                    pipe(
                        g.abundance,
                        O.fold(constant(''), (a) => a.abundance),
                    ),
                name: 'Abundance',
                sort: true,
                maxWidth: '150px',
            },
        ],
        [],
    );

    return (
        <>
            <Head>
                <title>Browse Galls</title>
            </Head>

            <Card>
                <Card.Body>
                    <Card.Title>Browse Galls</Card.Title>
                    <Form.Group className="mb-3">
                        <Form.Label>Filter</Form.Label>
                        <Form.Control
                            type="text"
                            placeholder="Search by name, aliases, or abundance..."
                            value={filterText}
                            onChange={handleFilterChange}
                        />
                    </Form.Group>
                    <div style={{ minHeight: '400px' }}>
                        <DataTable
                            keyField={'id'}
                            data={filteredItems}
                            columns={columns}
                            striped
                            noHeader
                            responsive={false}
                            defaultSortFieldId="name"
                            customStyles={TABLE_CUSTOM_STYLES}
                            pagination
                            paginationPerPage={25}
                            paginationRowsPerPageOptions={[10, 25, 50, 100]}
                            paginationServer={false}
                            paginationTotalRows={galls.length}
                        />
                    </div>
                </Card.Body>
            </Card>
        </>
    );
};

// Use static so that this stuff can be built once on the server-side and then cached.
export const getStaticProps: GetStaticProps = async () => {
    return {
        props: {
            galls: await getStaticPropsWith(allGalls, 'galls'),
        },
        revalidate: 1,
    };
};

export default BrowseGalls;
