import { pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetServerSideProps } from 'next';
import Link from 'next/link';
import { ParsedUrlQuery } from 'querystring';
import React from 'react';
import { Table } from 'react-bootstrap';
import { useSortableData } from '../hooks/use-sortabletable';
import { extractQueryParam } from '../libs/api/apipage';
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
};

const makeLink = (i: SearchResultItem) => {
    switch (i.type) {
        case 'gall':
            return (
                <Link href={`gall/${i.id}`}>
                    <a>{i.name}</a>
                </Link>
            );
        case 'plant':
            return (
                <Link href={`host/${i.id}`}>
                    <a>{i.name}</a>
                </Link>
            );
        case 'entry':
            return (
                <Link href={`glossary#${i.name}`}>
                    <a>{i.name}</a>
                </Link>
            );
        case 'source':
            return (
                <Link href={`source/${i.id}`}>
                    <a>{i.name}</a>
                </Link>
            );
        default:
            break;
    }
};

const imageForType = (type: string) => {
    switch (type) {
        case 'gall':
            return <img src="/images/gall.svg" alt="gallmaker" width="25px" height="25px" />;
        case 'plant':
            return <img src="/images/host.svg" alt="plant" width="25px" height="25px" />;
        case 'entry':
            return <img src="/images/entry.svg" alt="dictionary entry" width="25px" height="25px" />;
        case 'source':
            return <img src="/images/source.svg" alt="source" width="25px" height="25px" />;
        default:
            break;
    }
};

const GlobalSearch = ({ results }: Props): JSX.Element => {
    if (results.length <= 0) {
        return <h1>No results</h1>;
    }

    const { items, requestSort, sortConfig } = useSortableData(results, { key: 'name', direction: 'asc' });

    const getClassNamesFor = (name: keyof SearchResultItem): string => {
        return sortConfig.key === name ? sortConfig.direction : '';
    };

    return (
        <div className="fixed-left mt-2 ml-4 mr-2">
            <Table striped>
                <thead>
                    <tr>
                        <th className="thead-dark">
                            <button type="button" onClick={() => requestSort('type')} className={getClassNamesFor('type')}>
                                Type
                            </button>
                        </th>
                        <th>
                            <button type="button" onClick={() => requestSort('name')} className={getClassNamesFor('name')}>
                                Name
                            </button>
                        </th>
                    </tr>
                </thead>
                <tbody>
                    {items.map((s) => (
                        <tr key={s.id}>
                            <td>{imageForType(s.type)}</td>
                            <td>{makeLink(s)}</td>
                        </tr>
                    ))}
                </tbody>
            </Table>
            <style jsx>{`
                table {
                    width: 100%;
                    border-collapse: collapse;
                }

                thead th {
                    text-align: left;
                    border-bottom: 2px solid black;
                }

                thead button {
                    border: 0;
                    border-radius: none;
                    font-family: inherit;
                    font-weight: 700;
                    font-size: inherit;
                    padding: 0.5em;
                    margin-bottom: 1px;
                }

                thead button.asc::after {
                    content: '↑';
                    display: inline-block;
                    margin-left: 1em;
                }

                thead button.desc::after {
                    content: '↓';
                    display: inline-block;
                    margin-left: 1em;
                }

                tbody td {
                    padding: 0.5em;
                    border-bottom: 1px solid #ccc;
                }

                tbody tr:hover {
                    background-color: #eee;
                }
            `}</style>
        </div>
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
    });

    const { species, glossary, sources } = await mightFail(emptySearch)(globalSearch(search));
    // an experiment - lets mash them all together and show them in a single table

    const r: SearchResultItem[] = species
        .map((s) => ({ id: s.id.toString(), type: s.taxoncode, name: s.name }))
        .concat(glossary.map((g) => ({ id: g.word, type: 'entry', name: capitalizeFirstLetter(g.word) })))
        .concat(sources.map((s) => ({ id: s.id.toString(), type: 'source', name: s.title })));

    return {
        props: {
            results: r,
        },
    };
};

export default GlobalSearch;
