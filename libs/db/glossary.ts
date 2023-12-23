import { glossary, Prisma } from '@prisma/client';
import { pipe } from 'fp-ts/lib/function.js';
import * as TE from 'fp-ts/lib/TaskEither.js';
import { TaskEither } from 'fp-ts/lib/TaskEither.js';
import { DeleteResult, Entry, GlossaryEntryUpsertFields } from '../api/apitypes.js';
import { handleError } from '../utils/util.js';
import db from './db.js';

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
