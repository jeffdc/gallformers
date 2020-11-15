import { PorterStemmer, WordTokenizer } from 'natural';
import React from 'react';
import * as glossary from './glossary.json';
import { serialize } from './reactserialize';

export type Entry = {
    word: string;
    definition: string;
    urls: string[];
    seealso: string[];
};

export type EntryLinked = {
    word: string;
    linkedDefinition: string | JSX.Element[];
    definition: string;
    urls: string[];
    seealso: string[];
};

// ugly but I was unsure how to avoid this and keep TS happy
export const entries: Entry[] = (glossary as any)['default'].map((e: Entry) => e);

export interface WordStem {
    word: string;
    stem: string;
}

export const stems = entries.map((e) => {
    return <WordStem>{
        word: e.word,
        stem: PorterStemmer.stem(e.word),
    };
});

const makelink = (linkname: string, display: string, samepage: boolean): JSX.Element => {
    const href = samepage ? `#${linkname}` : `/glossary/#${linkname}`;
    return React.createElement('a', { href: href }, display);
};

// Given the input text, add links to any word that occurs in the global glossary.
// returns an array of strings/JSX.Elements.
export function linkTextFromGlossary(text: string | null | undefined, samepage = false): (string | JSX.Element)[] {
    const els: (string | JSX.Element)[] = [];

    if (text != undefined && text !== null && (text as string).length > 0) {
        let curr = 0;
        const tokens = new WordTokenizer().tokenize(text);
        tokens.forEach((t, i) => {
            const stemmed = PorterStemmer.stem(t);
            const raw = tokens[i];
            //  console.log(`t: '${t}' -- i: '${i}' -- stemmed: '${stemmed}' -- raw: '${raw}'`);
            stems.forEach((stem) => {
                if (stem.stem === stemmed) {
                    const left = text.substring(curr, text.indexOf(raw, curr));
                    curr = curr + left.length + raw.length;
                    // console.log(`\t left: '${left}' -- curr: '${curr}' -- raw: ${raw} -- stem: '${JSON.stringify(stem)}'`);

                    els.push(left);
                    els.push(makelink(stem.word, raw, samepage));
                }
            });
        });

        if (curr == 0) {
            // there were no words that matched so just put the whole text in
            els.push(text);
        } else if (curr < text.length) {
            // there is text leftover that we need to append
            els.push(text.substring(curr, text.length));
        }
    }

    return els;
}

/**
 * All of the Glossary entries with the definitions linked.
 */
export const entriesWithLinkedDefs: EntryLinked[] = entries.map((e) => {
    const entry: EntryLinked = {
        word: e.word,
        linkedDefinition: serialize(linkTextFromGlossary(e.definition, true)),
        definition: e.definition,
        urls: e.urls,
        seealso: e.seealso,
    };
    return entry;
});
