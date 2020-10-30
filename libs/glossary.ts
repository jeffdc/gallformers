import { PorterStemmer } from 'natural';
import React from 'react';
import * as glossary from './glossary.json';

export type Entry = {
    word: string,
    definition: string,
    urls: string[],
    seealso: string[]
}

// ugly but I was unsure how to avoid this and keep TS happy
export const entries: Entry[] = (glossary as any)["default"].map( (e: Entry) => e);

export const makelink = (linkname: string, display: string): JSX.Element => { 
    return React.createElement('a', { href: `#${linkname}`}, display) 
};

export interface MapEntry {
    word: string,
    stem: string
}

export const stems = entries.map( e => {
    return <MapEntry> {
        word: e.word,
        stem: PorterStemmer.stem(e.word)
    }
});