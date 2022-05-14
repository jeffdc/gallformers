import { pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetServerSideProps } from 'next';
import Head from 'next/head';
import Image from 'next/image';
import Link from 'next/link';
import { ParsedUrlQuery } from 'querystring';
import React, { useMemo } from 'react';
import { Col, Container, Row } from 'react-bootstrap';
import DataTable from '../components/DataTable';
import { extractQueryParam } from '../libs/api/apipage';
import { PlaceNoTreeApi } from '../libs/api/apitypes';
import { TaxonomyEntryNoParent } from '../libs/api/taxonomy';
import { globalSearch, GlobalSearchResults, TinySource, TinySpecies } from '../libs/db/search';
import { EntryLinked } from '../libs/pages/glossary';
import { formatWithDescription } from '../libs/pages/renderhelpers';
import { TABLE_CUSTOM_STYLES } from '../libs/utils/DataTableConstants';
import { logger } from '../libs/utils/logger';
import { capitalizeFirstLetter, mightFail } from '../libs/utils/util';

type SearchResultItem = {
    // we need a unique ID for the data table and to keep React happy. we can not just use the ID of the
    // item since we are mixing items of different type in the results and the likelihood of an ID clash
    // is quite likely.
    uid: string;
    id: string;
    type: string;
    name: string;
    aliases: string[];
};

type Props = {
    results: SearchResultItem[];
    search: string;
};

const imageForType = (i: SearchResultItem) => {
    switch (i.type) {
        case 'gall':
            return <Image src="/images/gall.svg" alt="gallformer" aria-label="gallformer" width="25px" height="25px" />;
        case 'plant':
            return <Image src="/images/host.svg" alt="plant" aria-label="plant" width="25px" height="25px" />;
        case 'entry':
            return <Image src="/images/entry.svg" alt="glossary entry" aria-label="glossary entry" width="25px" height="25px" />;
        case 'source':
            return <Image src="/images/source.svg" alt="source" aria-label="source" width="25px" height="25px" />;
        case 'genus':
            return <Image src="/images/taxon.svg" alt="genus" aria-label="genus" width="25px" height="25px" />;
        case 'section':
            return <Image src="/images/taxon.svg" alt="section" aria-label="section" width="25px" height="25px" />;
        case 'family':
            return <Image src="/images/taxon.svg" alt="family" aria-label="family" width="25px" height="25px" />;
        case 'place':
            return <Image src="/images/place.svg" alt="place" aria-label="place" width="25px" height="25px" />;
        default:
            return <></>;
    }
};

const linkItem = (i: SearchResultItem) => {
    switch (i.type) {
        case 'gall':
            return (
                <Link href={`/gall/${i.id}`}>
                    <a>
                        <em>{formatWithDescription(i.name, i.aliases, true)}</em>
                    </a>
                </Link>
            );
        case 'plant':
            return (
                <Link href={`/host/${i.id}`}>
                    <a>
                        <em>{formatWithDescription(i.name, i.aliases, true)}</em>
                    </a>
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
                    <a>
                        <em>{`Genus ${formatWithDescription(i.name, i.aliases, true)}`}</em>
                    </a>
                </Link>
            );
        case 'section':
            return (
                <Link href={`/section/${i.id}`}>
                    <a>
                        <em>{`Section ${formatWithDescription(i.name, i.aliases, true)}`}</em>
                    </a>
                </Link>
            );
        case 'family':
            return (
                <Link href={`/family/${i.id}`}>
                    <a>{`Family ${i.name}`}</a>
                </Link>
            );
        case 'place':
            return (
                <Link href={`/place/${i.id}`}>
                    <a>{i.name}</a>
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
                <meta name="description" content="Gallformer Search Results" />
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
                        keyField="uid"
                        data={results}
                        columns={columns}
                        striped
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
        places: new Array<PlaceNoTreeApi>(),
    });

    const { species, glossary, sources, taxa, places } = await mightFail(emptySearch)(globalSearch(search));
    // an experiment - lets mash them all together and show them in a single table

    const r: SearchResultItem[] = species
        .map((s) => ({ uid: `${s.id}-${s.taxoncode}`, id: s.id.toString(), type: s.taxoncode, name: s.name, aliases: s.aliases }))
        .concat(
            glossary.map((g) => ({
                uid: `${g.id}-entry`,
                id: g.word,
                type: 'entry',
                name: capitalizeFirstLetter(g.word),
                aliases: [],
            })),
        )
        .concat(sources.map((s) => ({ uid: `${s.id}-source`, id: s.id.toString(), type: 'source', name: s.source, aliases: [] })))
        .concat(
            places.map((p) => ({
                uid: `${p.id}-place`,
                id: p.id.toString(),
                type: 'place',
                name: `${p.name} - ${p.code}`,
                aliases: [],
            })),
        )
        .concat(
            taxa.map((t) => ({
                uid: `${t.id}-${t.type}`,
                id: t.id.toString(),
                type: t.type,
                name: t.name,
                aliases: t.description ? [t.description] : [],
            })),
        );

    return {
        props: {
            results: r,
            search: search,
        },
    };
};

export default GlobalSearch;
