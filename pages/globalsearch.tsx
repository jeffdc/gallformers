import { pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetServerSideProps } from 'next';
import Head from 'next/head';
import Link from 'next/link';
import { ParsedUrlQuery } from 'querystring';
import React from 'react';
import { Col, Container, Row } from 'react-bootstrap';
import BootstrapTable, { ColumnDescription } from 'react-bootstrap-table-next';
import { extractQueryParam } from '../libs/api/apipage';
import { TaxonomyEntryNoParent } from '../libs/api/taxonomy';
import { globalSearch, GlobalSearchResults, TinySource, TinySpecies } from '../libs/db/search';
import { EntryLinked } from '../libs/pages/glossary';
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

const imageForType = (cell: string, i: SearchResultItem) => {
    switch (i.type) {
        case 'gall':
            return <img src="/images/gall.svg" alt="gallmaker" width="25px" height="25px" />;
        case 'plant':
            return <img src="/images/host.svg" alt="plant" width="25px" height="25px" />;
        case 'entry':
            return <img src="/images/entry.svg" alt="dictionary entry" width="25px" height="25px" />;
        case 'source':
            return <img src="/images/source.svg" alt="source" width="25px" height="25px" />;
        case 'genus':
            return <img src="/images/taxon.svg" alt="source" width="25px" height="25px" />;
        case 'section':
            return <img src="/images/taxon.svg" alt="source" width="25px" height="25px" />;
        case 'family':
            return <img src="/images/taxon.svg" alt="source" width="25px" height="25px" />;
        default:
            return <></>;
    }
};

const linkItem = (cell: string, i: SearchResultItem) => {
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

const columns: ColumnDescription[] = [
    {
        dataField: 'type',
        text: 'Type',
        sort: true,
        formatter: imageForType,
    },
    {
        dataField: 'name',
        text: 'Name',
        sort: true,
        formatter: linkItem,
    },
];

const GlobalSearch = ({ results, search }: Props): JSX.Element => {
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
                    <BootstrapTable
                        keyField={'id'}
                        data={results}
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
