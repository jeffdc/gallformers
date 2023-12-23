import { GetStaticProps } from 'next';
import Head from 'next/head.js';
import { useMemo } from 'react';
import { Col, Container, Row } from 'react-bootstrap';
import DataTable from '../components/DataTable.js';
import Edit from '../components/edit.js';
import { Entry } from '../libs/api/apitypes.js';
import { allGlossaryEntries } from '../libs/db/glossary.js';
import { EntryLinked, linkDefinitionToGlossary } from '../libs/pages/glossary.js';
import { TABLE_CUSTOM_STYLES } from '../libs/utils/DataTableConstants.js';
import { mightFailWithArray } from '../libs/utils/util.js';

type Props = {
    es: EntryLinked[];
};

const formatRefs = (e: EntryLinked) => {
    const urls = e.urls.split('\n');
    if (urls === undefined || urls === null) {
        return <></>;
    }

    const refs = urls.map((url, i) => {
        return (
            <span key={i}>
                <a href={url} target="_blank" rel="noreferrer">
                    {i + 1}
                </a>
                {i < urls.length - 1 ? ', ' : ''}
            </span>
        );
    });

    return <>{refs}</>;
};

const formatWord = (e: EntryLinked) => {
    return (
        <div id={e.word.toLocaleLowerCase()}>
            <b>{e.word}</b>
            <Edit id={e.id} type="glossary" />
        </div>
    );
};

const formatDef = (e: EntryLinked) => {
    return <span className="padded-table-cell">{e.definition}</span>;
    // return (
    //     <ReactMarkdown rehypePlugins={[rehypeRaw]} remarkPlugins={[externalLinks, remarkBreaks]}>
    //         {e.definition}
    //     </ReactMarkdown>
    // );
};

const Glossary = ({ es }: Props): JSX.Element => {
    const columns = useMemo(
        () => [
            {
                id: 'word',
                selector: (row: EntryLinked) => row.word,
                name: 'Word',
                sortable: true,
                format: formatWord,
                wrap: true,
                maxWidth: '250px',
            },
            {
                id: 'definition',
                selector: (row: EntryLinked) => row.definition,
                name: 'Definition',
                format: formatDef,
                sortable: true,
                wrap: true,
            },
            {
                id: 'refs',
                selector: (g: EntryLinked) => g.urls,
                name: 'Refs',
                format: formatRefs,
                sort: true,
                wrap: true,
                maxWidth: '100px',
            },
        ],
        [],
    );

    if (es == undefined || es == null) {
        throw new Error('Invalid props passed to Glossary.');
    }
    return (
        <Container className="pt-2" fluid>
            <Head.default>
                <title>Glossary</title>
                <meta name="description" content="A Glossary of Gall Related Terminology" />
            </Head.default>
            <h1 className="ms-3 pt-3">A Glossary of Gall Related Terminology</h1>
            <Row className="p-3">
                <Col>
                    <DataTable
                        keyField={'id'}
                        data={es}
                        columns={columns}
                        striped
                        noHeader
                        responsive={false}
                        defaultSortFieldId="word"
                        customStyles={TABLE_CUSTOM_STYLES}
                    />
                </Col>
            </Row>
        </Container>
    );
};

export const getStaticProps: GetStaticProps = async () => {
    const entries = await mightFailWithArray<Entry>()(allGlossaryEntries());

    return {
        props: {
            es: await linkDefinitionToGlossary(entries),
        },
        revalidate: 1,
    };
};

export default Glossary;
