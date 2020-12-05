import { source } from '@prisma/client';
import { TaskEither } from 'fp-ts/lib/TaskEither';
import * as TE from 'fp-ts/lib/TaskEither';
import db from './db';
import { handleError } from '../utils/util';
import { extractId } from './utils';
import { pipe } from 'fp-ts/lib/function';
import { SourceUpsertFields } from '../apitypes';

export const sourceById = (id: number): TaskEither<Error, source[]> => {
    const sources = () =>
        db.source.findMany({
            where: { id: { equals: id } },
        });

    return TE.tryCatch(sources, handleError);
};

export const allSources = (): TaskEither<Error, source[]> => {
    const sources = () =>
        db.source.findMany({
            orderBy: { title: 'asc' },
        });

    return TE.tryCatch(sources, handleError);
};

export const allSourceIds = (): TaskEither<Error, string[]> => {
    const ids = () => db.source.findMany({ select: { id: true } });

    // eslint-disable-next-line prettier/prettier
    return pipe(
        TE.tryCatch(ids, handleError),
        TE.map((i) => i.map(extractId).map((x) => x.toString())),
    );
};

export const upsertSource = (source: SourceUpsertFields): TaskEither<Error, number> => {
    const upsert = () =>
        db.source.upsert({
            where: { title: source.title },
            update: {
                author: source.author,
                citation: source.citation,
                link: source.link,
                pubyear: source.pubyear,
            },
            create: {
                author: source.author,
                citation: source.citation,
                link: source.link,
                pubyear: source.pubyear,
                title: source.title,
            },
        });

    return pipe(
        TE.tryCatch(upsert, handleError),
        TE.map((s) => s.id),
    );
};
