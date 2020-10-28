import { GetServerSideProps } from 'next';
import React, { Fragment } from 'react';
import { ListGroup } from 'react-bootstrap';
import * as glossary from './glossary.json'

type Word = {
    word: string,
    defintion: JSX.Element,
    urls: string[],
    seealso : string[]
}
type Props = {
    words: Word[]
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

const Glossary = ({ words }: Props ): JSX.Element => {
    return (
        <div>
            <ListGroup className='m-2 p-2'>
                {words.map( w =>
                    <ListGroup.Item key={w.word}>
                        <span id={w.word}>
                            <b>{w.word} - </b>{w.defintion}
                            {renderrefs(w.urls)}
                        </span>
                    </ListGroup.Item>
                )}
            </ListGroup>
        </div>
    )
}

type Entry = {
    word: string,
    defintion: string,
    urls: string[],
    seealso: string[]
}

export const getServerSideProps: GetServerSideProps = async () => {
    // add links to all words that appear in the glossary that are part of another word's definition
    // ugly but I was unsure how to avoid this and keep TS happy
    const entries: Entry[] = (glossary as any)["default"].map( (e: Entry) => e);

    
    return {
        props: {
           words: entries
        }
    }
}

export default Glossary;