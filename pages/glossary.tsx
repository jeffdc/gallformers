import { GetStaticProps } from 'next';
import React from 'react';
import { ListGroup } from 'react-bootstrap';
import { entriesWithLinkedDefs, EntryLinked } from '../libs/glossary';
import { deserialize } from '../libs/reactserialize';

type Props = {
    es: EntryLinked[];
};

const renderrefs = (urls: string[]) => {
    if (urls === undefined || urls === null) {
        return <></>;
    }

    const refs = urls.map((url, i) => {
        return (
            <sup key={i}>
                <a href={url} key={i}>
                    {i + 1}&nbsp;
                </a>
            </sup>
        );
    });

    return refs;
};

const Glossary = ({ es }: Props): JSX.Element => {
    if (es == undefined || es == null) {
        throw new Error('Invalid props passed to Glossary.');
    }
    return (
        <div>
            <h1 className="ml-3 pt-3">A Glossary of Gall Related Terminology</h1>
            <ListGroup className="m-2 p-2">
                {es.map((e) => (
                    <ListGroup.Item key={e.word}>
                        <span id={e.word}>
                            <b>{e.word} - </b>
                            {deserialize(e.linkedDefinition)}
                            {renderrefs(e.urls)}
                        </span>
                    </ListGroup.Item>
                ))}
            </ListGroup>
        </div>
    );
};

export const getStaticProps: GetStaticProps = async () => {
    return {
        props: {
            es: entriesWithLinkedDefs,
        },
    };
};

export default Glossary;
