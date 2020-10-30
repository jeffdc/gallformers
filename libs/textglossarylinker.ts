import { stems, makelink } from './glossary'
import { WordTokenizer, PorterStemmer } from 'natural'

const falsefunc = (_s: string) => false;
// Given the input text, add links to any word that occurs in the global glossary.
// returns an array of strings/JSX.Elements. 
export function linkTextFromGlossary(text: (string | null | undefined), 
                                     unless: ((w: string) => boolean) = (falsefunc),
                                     samepage = false): (string | JSX.Element)[] {
    const els: (string | JSX.Element)[] = []

    if (text != undefined && text !== null && (text as string).length > 0) {
        let curr = 0;
        const tokens = new WordTokenizer().tokenize(text);
        tokens.forEach( (t, i) => {
            const stemmed = PorterStemmer.stem(t);
            const raw = tokens[i];
//  console.log(`t: '${t}' -- i: '${i}' -- stemmed: '${stemmed}' -- raw: '${raw}'`);
            stems.forEach( stem => {
                if (stem.stem === stemmed && !unless(stemmed)) {
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

    return els
}