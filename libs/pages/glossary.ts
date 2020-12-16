import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import * as TE from 'fp-ts/lib/TaskEither';
import { TaskEither } from 'fp-ts/lib/TaskEither';
import { PorterStemmer, WordTokenizer } from 'natural';
import React, { ReactNode } from 'react';
import { allGlossaryEntries, Entry } from '../db/glossary';
import { serialize } from '../utils/reactserialize';

export type EntryLinked = Entry & {
    linkedDefinition: string | JSX.Element[];
};

type WordStem = {
    word: string;
    stem: string;
};

const makeLink = (linkname: string, display: string, samepage: boolean): JSX.Element => {
    const href = samepage ? `#${linkname}` : `/glossary/#${linkname}`;
    return React.createElement('a', { href: href }, display);
};

const stemText = (es: Entry[]): WordStem[] =>
    es.map((e) => {
        return {
            ...e,
            stem: PorterStemmer.stem(e.word),
        };
    });

const linkFromStems = (text: string, samepage: boolean) => (stems: WordStem[]): ReactNode[] => {
    const els: ReactNode[] = [];
    let curr = 0;
    const tokens = new WordTokenizer().tokenize(text);
    tokens.forEach((t, i) => {
        const stemmed = PorterStemmer.stem(t);
        const raw = tokens[i];

        stems.forEach((stem) => {
            if (stem.stem === stemmed) {
                const left = text.substring(curr, text.indexOf(raw, curr));
                curr = curr + left.length + raw.length;

                els.push(left);
                els.push(makeLink(stem.word, raw, samepage));
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
    return els;
};

/** Make the helper functions available for unit testing. */
export const testables = {
    makeLink: makeLink,
    stemText: stemText,
    linkFromStems: linkFromStems,
};

/**
 * Given the input text, add links to any word that occurs in the global glossary.
 *
 * @param text the text to find and link glossary terms in.
 * @param samepage a flag to signify if the links are on the same page.
 */
export function linkTextFromGlossary(text: O.Option<string>, samepage = false): TaskEither<Error, ReactNode[]> {
    // eslint-disable-next-line prettier/prettier
    return pipe(
        allGlossaryEntries(),
        TE.map(stemText),
        TE.map((stems) =>
            pipe(
                text,
                TE.fromOption(constant(new Error('Received invalid text.'))),
                TE.map((text) => linkFromStems(text, samepage)(stems)),
            ),
        ),
        TE.flatten,
    );
}

/**
 * All of the Glossary entries with the definitions linked.
 */
export const entriesWithLinkedDefs = (): TaskEither<Error, readonly EntryLinked[]> => {
    const linkEntry = (e: Entry) => (def: string): EntryLinked => {
        return {
            ...e,
            linkedDefinition: def,
        };
    };

    const linkEntries = (es: Entry[]): TaskEither<Error, EntryLinked>[] => {
        return es.map((e) => {
            // eslint-disable-next-line prettier/prettier
            return pipe(
                linkTextFromGlossary(O.fromNullable(e.definition), true),
                TE.map(serialize),
                TE.map(linkEntry(e)),
            );
        });
    };

    // eslint-disable-next-line prettier/prettier
    return pipe(
        allGlossaryEntries(),
        TE.map(linkEntries),
        // deal with the fact that we have a TE<Error, LinkedEntry>[] but want a TE<Error, LinkedEntry[]>
        TE.map(TE.sequenceArray),
        TE.flatten,
    );
};
