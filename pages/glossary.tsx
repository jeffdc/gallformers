import { GetStaticProps } from 'next';
import Head from 'next/head';
import React from 'react';
import { Col, Row } from 'react-bootstrap';
import BootstrapTable, { ColumnDescription } from 'react-bootstrap-table-next';
import ReactMarkdown from 'react-markdown';
import rehypeRaw from 'rehype-raw';
import remarkBreaks from 'remark-breaks';
import externalLinks from 'remark-external-links';
import Edit from '../components/edit';
import { allGlossaryEntries, Entry } from '../libs/db/glossary';
import { EntryLinked, linkDefintionToGlossary } from '../libs/pages/glossary';
import { mightFailWithArray } from '../libs/utils/util';

type Props = {
    es: EntryLinked[];
};

const formatRefs = (cell: string, e: EntryLinked) => {
    const urls = e.urls.split('\n');
    if (urls === undefined || urls === null) {
        return <></>;
    }

    const refs = urls.map((url, i) => {
        return (
            <a href={url} key={i} target="_blank" rel="noreferrer">
                {i + 1}
                {i < urls.length - 1 ? ', ' : ''}
            </a>
        );
    });

    return <>{refs}</>;
};

const formatWord = (cell: string, e: EntryLinked) => {
    return (
        <p id={e.word.toLocaleLowerCase()}>
            <b>{e.word}</b>
            <Edit id={e.id} type="glossary" />
        </p>
    );
};

const formatDef = (cell: string, e: EntryLinked) => {
    return (
        <ReactMarkdown rehypePlugins={[rehypeRaw]} remarkPlugins={[externalLinks, remarkBreaks]}>
            {e.definition}
        </ReactMarkdown>
    );
};

const columns: ColumnDescription[] = [
    {
        dataField: 'word',
        text: 'Word',
        formatter: formatWord,
    },
    {
        dataField: 'definition',
        text: 'Definition',
        formatter: formatDef,
    },
    {
        dataField: 'urls',
        text: 'Refs',
        formatter: formatRefs,
    },
];

const Glossary = ({ es }: Props): JSX.Element => {
    if (es == undefined || es == null) {
        throw new Error('Invalid props passed to Glossary.');
    }
    return (
        <div>
            <Head>
                <title>Glossary</title>
            </Head>
            <h1 className="ml-3 pt-3">A Glossary of Gall Related Terminology</h1>
            <Row className="p-3">
                <Col>
                    <BootstrapTable
                        keyField={'id'}
                        data={es}
                        columns={columns}
                        bootstrap4
                        striped
                        headerClasses="table-header"
                        defaultSorted={[
                            {
                                dataField: 'word',
                                order: 'asc',
                            },
                        ]}
                    />
                </Col>
            </Row>
        </div>
    );
};

export const getStaticProps: GetStaticProps = async () => {
    const entries = await mightFailWithArray<Entry>()(allGlossaryEntries());

    return {
        props: {
            es: await linkDefintionToGlossary(entries),
        },
        revalidate: 1,
    };
};

export default Glossary;
