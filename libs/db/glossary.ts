import { glossary, Prisma } from '@prisma/client';
import { pipe } from 'fp-ts/lib/function';
import * as TE from 'fp-ts/lib/TaskEither';
import { TaskEither } from 'fp-ts/lib/TaskEither';
import { DeleteResult, Entry, GlossaryEntryUpsertFields } from '../api/apitypes';
import { handleError } from '../utils/util';
import db from './db';

const adaptor = (e: glossary): Entry => e;

export const allGlossaryEntries = (): TaskEither<Error, Entry[]> => {
    const glossary = () =>
        // prisma does not handle sort order by collate NOCASE
        // https://github.com/prisma/prisma/issues/5068
        db.$queryRaw<glossary[]>(Prisma.sql`
            SELECT * from glossary
            ORDER BY word COLLATE NOCASE ASC;
        `);

    return pipe(
        TE.tryCatch(glossary, handleError),
        TE.map((e) => e.map(adaptor)),
    );
};

export const deleteGlossaryEntry = (id: number): TaskEither<Error, DeleteResult> => {
    const results = () =>
        db.glossary.delete({
            where: { id: id },
            select: { word: true },
        });

    const toDeleteResult = (result: { word: string }): DeleteResult => {
        return {
            type: 'glossary',
            name: result.word,
            count: 1,
        };
    };
    // eslint-disable-next-line prettier/prettier
    return pipe(
        TE.tryCatch(results, handleError),
        TE.map(toDeleteResult),
    );
};

export const upsertGlossary = (entry: GlossaryEntryUpsertFields): TaskEither<Error, Entry> => {
    const upsert = () =>
        db.glossary.upsert({
            where: { id: entry.id },
            update: {
                word: entry.word,
                definition: entry.definition,
                urls: entry.urls,
            },
            create: {
                word: entry.word,
                definition: entry.definition,
                urls: entry.urls,
            },
        });

    // eslint-disable-next-line prettier/prettier
    return pipe(
        TE.tryCatch(upsert, handleError),
        TE.map(adaptor),
    );
};

/**
 * A general way to fetch glossary entries. Check this file for pre-defined helpers that are easier to use.
 * @param whereClause a where clause by which to filter places
 */
export const getEntries = (whereClause: Prisma.glossaryWhereInput): TaskEither<Error, Entry[]> => {
    const entries = () =>
        db.glossary.findMany({
            where: whereClause,
            orderBy: { word: 'asc' },
        });

    return TE.tryCatch(entries, handleError);
};

/**
 * A way to search for glossary entries.
 * @param s the string to search for, will search only on the glossary entry Words
 * @returns an array of results
 */
export const searchGlossary = (s: string): TaskEither<Error, Entry[]> => {
    return getEntries({ word: { contains: s } });
};

/**
 *
 * @param word Exact match on a glossary word adn return it if it exists
 * @returns An array containing the Entry if it is found, otherwise an empty array.
 */
export const getEntryByWord = (word: string): TaskEither<Error, Entry[]> => {
    return getEntries({ word: { equals: word } });
};
