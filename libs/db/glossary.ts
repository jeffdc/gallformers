import { glossary } from '@prisma/client';
import { pipe } from 'fp-ts/lib/function';
import * as TE from 'fp-ts/lib/TaskEither';
import { TaskEither } from 'fp-ts/lib/TaskEither';
import { DeleteResult, GlossaryEntryUpsertFields } from '../apitypes';
import { handleError } from '../utils/util';
import db from './db';

export type Entry = {
    id: number;
    word: string;
    definition: string;
    urls: string[];
};

export const allGlossaryEntries = (): TaskEither<Error, Entry[]> => {
    const glossary = () =>
        db.glossary.findMany({
            orderBy: { word: 'asc' },
        });

    const glossaryToEntry = (e: glossary): Entry => {
        return {
            ...e,
            urls: e.urls.split('\n'),
        };
    };

    return pipe(
        TE.tryCatch(glossary, handleError),
        TE.map((e) => e.map(glossaryToEntry)),
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

export const upsertGlossary = (entry: GlossaryEntryUpsertFields): TaskEither<Error, string> => {
    const upsert = () =>
        db.glossary.upsert({
            where: { word: entry.word },
            update: {
                definition: entry.definition,
                urls: entry.urls,
            },
            create: {
                word: entry.word,
                definition: entry.definition,
                urls: entry.urls,
            },
        });

    return pipe(
        TE.tryCatch(upsert, handleError),
        TE.map((e) => e.word),
    );
};
