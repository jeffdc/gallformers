import * as A from 'fp-ts/lib/Array.js';
import { constant, pipe } from 'fp-ts/lib/function.js';
import * as O from 'fp-ts/lib/Option.js';
import * as TE from 'fp-ts/lib/TaskEither.js';
import { PorterStemmer, WordTokenizer } from 'natural';
import { Entry, SpeciesSourceApi } from '../api/apitypes.js';
import { allGlossaryEntries } from '../db/glossary.js';
import { errorThrow } from '../utils/util.js';

export type EntryLinked = Entry & {
    linkedDefinition: string | JSX.Element[];
};

type WordStem = {
    word: string;
    stem: string;
};

type Context = {
    stems: WordStem[];
    glossary: Entry[];
};

const stemText = (es: Entry[]): WordStem[] =>
    es.map((e) => {
        return {
            ...e,
            stem: PorterStemmer.stem(e.word),
        };
    });

//TODO - this is a bad implementation. Figure out how to use Popper (via bootstrap OverlayTrigger). Not clear
// how to inject a React component in to the Markdown...
const makeLinkHtml = (display: string, entry: Entry | undefined): string => {
    return `<span class="jargon-term"><a href="/glossary/#${entry?.word}">${display}</a><span class="jargon-info">${entry?.definition}</span></span>`;
};

const linkHtml =
    (context: Context) =>
    (text: string): string => {
        const els: string[] = [];
        let curr = 0;
        const tokens = new WordTokenizer().tokenize(text);
        tokens?.forEach((t, i) => {
            const stemmed = PorterStemmer.stem(t);
            const raw = tokens[i];

            context.stems.forEach((stem) => {
                if (stem.stem === stemmed) {
                    const left = text.substring(curr, text.indexOf(raw, curr));
                    curr = curr + left.length + raw.length;

                    els.push(left);
                    els.push(
                        makeLinkHtml(
                            raw,
                            context.glossary.find((e) => e.word === stem.word),
                        ),
                    );
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
        return els.reduce((acc, s) => acc.concat(s), '');
    };

// const linkHtml2 =
//     (context: Context) =>
//     (text: string): string => {
//         let s = '';
//         remark()
//             .use(remarkGlossary, { glossary: context.glossary, stems: context.stems })
//             .process(text, (e, f) => {
//                 if (e) throw e;
//                 console.log(`JDC: ${JSON.stringify(f, null, '  ')}`);
//                 s = f.toString();
//             });

//         return s;
//     };

/** Make the helper functions available for unit testing. */
export const testables = {
    makeLinkHtml: makeLinkHtml,
    stemText: stemText,
    linkHtml: linkHtml,
};

const internalLinker = async <T>(data: T[], update: (d: string, t: T) => T, getVal: (t: T) => string | undefined) => {
    const toContext = (glossary: Entry[]): Context => ({ stems: stemText(glossary), glossary: glossary });

    const linkText =
        () =>
        (s: (typeof data)[0]): TE.TaskEither<Error, string> =>
            pipe(
                O.fromNullable(getVal(s)),
                TE.fromOption(constant(new Error('Received invalid text.'))),
                // for now turning this off while I work on a new solution.
                // TE.map(linkHtml(context)),
                // TE.map(linkHtml2(context)),
            );

    return await pipe(
        allGlossaryEntries(),
        TE.map(toContext),
        TE.chain(() =>
            pipe(
                data,
                A.map(linkText()),
                TE.sequenceArray,
                // sequence makes the array readonly, the rest of the fp-ts API does not use readonly, ...sigh.
                TE.map((d) => A.zipWith(d as string[], data, update)),
            ),
        ),
        TE.getOrElse(errorThrow),
    )();
};

/**
 *
 * @param data
 * @returns
 */
export const linkSourceToGlossary = async (data: SpeciesSourceApi[]): Promise<SpeciesSourceApi[]> => {
    const update = (d: string, t: SpeciesSourceApi): SpeciesSourceApi => {
        return {
            ...t,
            description: d,
        };
    };

    return await internalLinker(data, update, (e: SpeciesSourceApi) => e.description);
};

export const linkDefinitionToGlossary = async (data: Entry[]): Promise<Entry[]> => {
    const update = (d: string, e: Entry): Entry => ({
        ...e,
        definition: d,
    });

    return await internalLinker(data, update, (e: Entry) => e.definition);
};
