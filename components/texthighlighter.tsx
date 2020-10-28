import { GetServerSideProps } from "next";
import React from "react";

type Props = {
    text: string
}

const TextHighlighter = ({ text }: Props): JSX.Element => {
    return (
        <>
            {text}
        </>
    )
}

// const makelink = (w: string) => { return (<a href={`#${w}`}>{w}</a>) };

// export const getServerSideProps: GetServerSideProps = async () => {
//     // add links to all words that appear in the glossary that are part of another word's definition
//     // ugly but I was unsure how to avoid this and keep TS happy
//     const entries: Entry[] = (glossary as any)["default"].map( (e: Entry) => e);

//     const wordMap = entries.map( w => {
//         const foo = {
//             word: w.word,
//             link: makelink(w.defintion as string)
//         } as MapEntry
//         return foo
//     });

//     const newEntries = entries.map( entry => {
//         const highlightedDef = Object.keys(wordMap).map( w => {
//             const regex = new RegExp("\\b" + w + "\\b");
//             const matches = (entry.defintion as string).match(regex);
//             const parts = (entry.defintion as string).split(regex);
//             // console.log(`matches = ${JSON.stringify(matches, null, '  ')}`);
//             // console.log(`parts = ${JSON.stringify(parts, null, '  ')}`);
//             if (!matches || entry.word === w) {
//                 return (<Fragment key={entry.word}>{entry.defintion}</Fragment>)
//             }
//             return (
//                 <Fragment key={entry.word + w}>{ parts.map( (part, idx) => (
//                     <Fragment key={part + idx}>{part} {(wordMap as any)[w]}</Fragment>
//                 )) }</Fragment>)
//         });

//         console.log(`${JSON.stringify(highlightedDef, null, '  ')}`);
//         return {
//             word: entry.word,
//             definition: highlightedDef,
//             urls: entry.urls,
//             seealso: entry.seealso
//         }
//     });

//     // console.log(`${JSON.stringify(newEntries, null, '  ')}`);

//     return {
//         props: {
//            words: newEntries
//         }
//     }
// }

export default TextHighlighter;