import { pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetServerSideProps } from 'next';
import Head from 'next/head';
import Link from 'next/link';
import { ParsedUrlQuery } from 'querystring';
import React, { useMemo } from 'react';
import { Col, Container, Row } from 'react-bootstrap';
import DataTable from 'react-data-table-component';
import { extractQueryParam } from '../libs/api/apipage';
import { TaxonomyEntryNoParent } from '../libs/api/taxonomy';
import { globalSearch, GlobalSearchResults, TinySource, TinySpecies } from '../libs/db/search';
import { EntryLinked } from '../libs/pages/glossary';
import { TABLE_CUSTOM_STYLES } from '../libs/utils/DataTableConstants';
import { logger } from '../libs/utils/logger';
import { capitalizeFirstLetter, mightFail } from '../libs/utils/util';

type SearchResultItem = {
    id: string;
    type: string;
    name: string;
};

type Props = {
    results: SearchResultItem[];
    search: string;
};

const imageForType = (i: SearchResultItem) => {
    switch (i.type) {
        case 'gall':
            return <img src="/images/gall.svg" alt="gallformer" aria-label="gallformer" width="25px" height="25px" />;
        case 'plant':
            return <img src="/images/host.svg" alt="plant" aria-label="plant" width="25px" height="25px" />;
        case 'entry':
            return <img src="/images/entry.svg" alt="glossary entry" aria-label="glossary entry" width="25px" height="25px" />;
        case 'source':
            return <img src="/images/source.svg" alt="source" aria-label="source" width="25px" height="25px" />;
        case 'genus':
            return <img src="/images/taxon.svg" alt="genus" aria-label="genus" width="25px" height="25px" />;
        case 'section':
            return <img src="/images/taxon.svg" alt="section" aria-label="section" width="25px" height="25px" />;
        case 'family':
            return <img src="/images/taxon.svg" alt="family" aria-label="family" width="25px" height="25px" />;
        default:
            return <></>;
    }
};

const linkItem = (i: SearchResultItem) => {
    switch (i.type) {
        case 'gall':
            return (
                <Link href={`/gall/${i.id}`}>
                    <a>{i.name}</a>
                </Link>
            );
        case 'plant':
            return (
                <Link href={`/host/${i.id}`}>
                    <a>{i.name}</a>
                </Link>
            );
        case 'entry':
            return (
                <Link href={`/glossary#${i.name.toLocaleLowerCase()}`}>
                    <a>{i.name}</a>
                </Link>
            );
        case 'source':
            return (
                <Link href={`/source/${i.id}`}>
                    <a>{i.name}</a>
                </Link>
            );
        case 'genus':
            return (
                <Link href={`/genus/${i.id}`}>
                    <a>{`Genus ${i.name}`}</a>
                </Link>
            );
        case 'section':
            return (
                <Link href={`/section/${i.id}`}>
                    <a>{`Section ${i.name}`}</a>
                </Link>
            );
        case 'family':
            return (
                <Link href={`/family/${i.id}`}>
                    <a>{`Family ${i.name}`}</a>
                </Link>
            );
        default:
            return <></>;
    }
};

const GlobalSearch = ({ results, search }: Props): JSX.Element => {
    const columns = useMemo(
        () => [
            {
                id: 'type',
                selector: (row: SearchResultItem) => row.type,
                name: 'Type',
                sortable: true,
                center: true,
                compact: true,
                maxWidth: '100px',
                format: imageForType,
            },
            {
                id: 'name',
                selector: (row: SearchResultItem) => row.name,
                name: 'Name',
                sortable: true,
                wrap: true,
                format: linkItem,
            },
        ],
        [],
    );

    return (
        <Container className="pt-2" fluid>
            <Head>
                <title>Search Results - {`'${search}'`}</title>
            </Head>

            {results.length <= 0 && (
                <Row className="p-2">
                    <Col>
                        <strong>No results for {`'${search}'`}</strong>
                    </Col>
                </Row>
            )}
            <Row>
                <Col xs={12}>
                    <DataTable
                        keyField={'id'}
                        data={results}
                        columns={columns}
                        striped
                        dense
                        noHeader
                        fixedHeader
                        responsive={false}
                        defaultSortFieldId="pubyear"
                        customStyles={TABLE_CUSTOM_STYLES}
                    />
                </Col>
            </Row>
        </Container>
    );
};

export const getServerSideProps: GetServerSideProps = async (context: { query: ParsedUrlQuery }) => {
    const queryParam = 'searchText';
    const search = pipe(
        extractQueryParam(context.query, queryParam),
        O.getOrElse(() => {
            logger.error(`Failed to find the expected query parameter ${queryParam}.`);
            return '';
        }),
    );

    const emptySearch = (): GlobalSearchResults => ({
        species: new Array<TinySpecies>(),
        glossary: new Array<EntryLinked>(),
        sources: new Array<TinySource>(),
        taxa: new Array<TaxonomyEntryNoParent>(),
    });

    const { species, glossary, sources, taxa } = await mightFail(emptySearch)(globalSearch(search));
    // an experiment - lets mash them all together and show them in a single table

    const r: SearchResultItem[] = species
        .map((s) => ({ id: s.id.toString(), type: s.taxoncode, name: s.name }))
        .concat(glossary.map((g) => ({ id: g.word, type: 'entry', name: capitalizeFirstLetter(g.word) })))
        .concat(sources.map((s) => ({ id: s.id.toString(), type: 'source', name: s.source })))
        .concat(taxa.map((t) => ({ id: t.id.toString(), type: t.type, name: t.name })));

    return {
        props: {
            results: r,
            search: search,
        },
    };
};

export default GlobalSearch;
