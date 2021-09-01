export {};
// import { PorterStemmer, WordTokenizer } from 'natural';
// import { Plugin, Transformer, Settings } from 'unified/types/ts4.0/index';
// import { Node } from 'unist';
// import visit from 'unist-util-visit';
// import { Entry } from '../db/glossary';
// import { Text } from 'mdast';

// export type WordStem = {
//     word: string;
//     stem: string;
// };

// export type Context = {
//     stems: WordStem[];
//     glossary: Entry[];
// };

// type RemarkGlossarySettings = Settings & {
//     stems: WordStem[];
//     glossary: Entry[];
// };

// const makeLinkHtml = (display: string, entry: Entry | undefined): string => {
//     return `<span class="jargon-term"><a href="/glossary/#${entry?.word}">${display}</a><span class="jargon-info">${entry?.definition}</span></span>`;
// };

// const remarkGlossary: Plugin<RemarkGlossarySettings[]> = (settings: RemarkGlossarySettings) => {
//     const transform: Transformer = (tree: Node) => {
//         const visitor: visit.Visitor<Text> = (node: Text) => {
//             const text = node.value;
//             const els: string[] = [];
//             let curr = 0;
//             const tokens = new WordTokenizer().tokenize(text);
//             tokens.forEach((t, i) => {
//                 const stemmed = PorterStemmer.stem(t);
//                 const raw = tokens[i];

//                 settings.stems.forEach((stem) => {
//                     if (stem.stem === stemmed) {
//                         const left = text.substring(curr, text.indexOf(raw, curr));
//                         curr = curr + left.length + raw.length;

//                         els.push(left);
//                         els.push(
//                             makeLinkHtml(
//                                 raw,
//                                 settings.glossary.find((e) => e.word === stem.word),
//                             ),
//                         );
//                     }
//                 });
//             });

//             if (curr == 0) {
//                 // there were no words that matched so just put the whole text in
//                 els.push(text);
//             } else if (curr < text.length) {
//                 // there is text leftover that we need to append
//                 els.push(text.substring(curr, text.length));
//             }
//             els.reduce((acc, s) => acc.concat(s), '');
//             // return used to be.
//         };

//         visit(tree, 'text', visitor);
//     };

//     return transform;
// };

// export default remarkGlossary;
