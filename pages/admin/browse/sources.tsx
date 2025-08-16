import { GetStaticProps } from 'next';
import Head from 'next/head';
import Link from 'next/link';
import React, { useState } from 'react';
import { Card, Form } from 'react-bootstrap';
import Edit from '../../../components/edit';
import { SourceApi } from '../../../libs/api/apitypes';
import { allSources } from '../../../libs/db/source';
import { getStaticPropsWith } from '../../../libs/pages/nextPageHelpers';
import { TABLE_CUSTOM_STYLES } from '../../../libs/utils/DataTableConstants';
import DataTable from '../../../components/DataTable';

type Props = {
    sources: SourceApi[];
};

const linkSource = (s: SourceApi) => {
    return (
        <>
            <Link key={s.id} href={`/source/${s.id}`}>
                {s.title}
            </Link>
            <Edit id={s.id} type="source" />
        </>
    );
};

const BrowseSources = ({ sources }: Props): JSX.Element => {
    const [filterText, setFilterText] = useState('');
    const [filteredItems, setFilteredItems] = useState(sources);

    const handleFilterChange = (e: React.ChangeEvent<HTMLInputElement>) => {
        const value = e.target.value;
        setFilterText(value);

        if (!value) {
            setFilteredItems(sources);
            return;
        }

        const filtered = sources.filter((item) => {
            const searchValue = value.toLowerCase();
            const titleMatch = item.title?.toLowerCase().includes(searchValue) ?? false;
            const authorMatch = item.author?.toLowerCase().includes(searchValue) ?? false;
            const yearMatch = item.pubyear?.toLowerCase().includes(searchValue) ?? false;
            const citationMatch = item.citation?.toLowerCase().includes(searchValue) ?? false;

            return titleMatch || authorMatch || yearMatch || citationMatch;
        });

        setFilteredItems(filtered);
    };

    const columns = [
        {
            id: 'title',
            selector: (row: SourceApi) => row.title,
            name: 'Title',
            sortable: true,
            format: linkSource,
            maxWidth: '250px',
        },
        {
            id: 'author',
            selector: (row: SourceApi) => row.author,
            name: 'Author',
            sortable: true,
            wrap: true,
        },
        {
            id: 'pubyear',
            selector: (row: SourceApi) => row.pubyear,
            name: 'Year',
            sortable: true,
            maxWidth: '100px',
        },
        {
            id: 'citation',
            selector: (row: SourceApi) => row.citation,
            name: 'Citation',
            sortable: true,
            wrap: true,
        },
    ];

    return (
        <>
            <Head>
                <title>Browse Sources</title>
            </Head>

            <Card>
                <Card.Body>
                    <Card.Title>Browse Sources</Card.Title>
                    <Form.Group className="mb-3">
                        <Form.Label>Filter</Form.Label>
                        <Form.Control
                            type="text"
                            placeholder="Search by name, author, year, or title..."
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
            sources: await getStaticPropsWith(allSources, 'sources'),
        },
        revalidate: 1,
    };
};

export default BrowseSources;
