import { GetServerSideProps } from 'next';
import React from 'react';
import { ListGroup } from 'react-bootstrap';
import { linkTextFromGlossary } from '../libs/textglossarylinker';
import { entries } from '../libs/glossary'
import { serialize, deserialize } from '../libs/reactserialize'
import { PorterStemmer } from 'natural';

export type E = {
    word: string,
    definition: (string | JSX.Element[]),
    urls: string[],
    seealso: string[]
}

type Props = {
    es: E[]
}

const renderrefs = (urls: string[]) => {
    if (urls === undefined || urls === null) {
        return (<></>)
    }

    const refs = urls.map( (url, i) => {
        return (<sup key={i}><a href={url} key={i}>{i+1}&nbsp;</a></sup>)
    });

    return refs
}

const Glossary = ({ es }: Props ): JSX.Element => {
    if (es == undefined || es == null) {
        throw new Error('Invalid props passed to Glossary.')
    }
    return (
        <div>
            <h1 className='ml-3 pt-3'>A Glossary of Gall Related Terminology</h1>
            <ListGroup className='m-2 p-2'>
                {es.map( e =>
                    <ListGroup.Item key={e.word}>
                        <span id={e.word}>
                            <b>{e.word} - </b>{deserialize(e.definition)}
                            {renderrefs(e.urls)}
                        </span>
                    </ListGroup.Item>
                )}
            </ListGroup>
        </div>
    )
}

export const getServerSideProps: GetServerSideProps = async () => {
    // function that generates functions to pass to the glossary linker so that we do not link to the word being defined in its own
    // defintion.
    const curryUnless = (w1: string) => { 
        return (w: string) => { 
            return PorterStemmer.stem(w1) === w 
        } 
    };

    const es = entries.map( e => {
        const entry: E = {
            word: e.word,
            definition: serialize(linkTextFromGlossary(e.definition, curryUnless(e.word), true)),
            urls: e.urls,
            seealso: e.seealso
        }
        return entry
    });

    return {
        props: {
           es: es
        }
    }
}

export default Glossary;