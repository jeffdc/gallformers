import { source } from '@prisma/client';
import { Maybe } from 'true-myth';
import db from './db';

export const sourceById = async (id: number): Promise<Maybe<source>> => {
    return db.source
        .findFirst({
            where: { id: { equals: id } },
        })
        .then((s) => Maybe.of(s));
};

export const allSources = async (): Promise<source[]> => {
    return db.source.findMany({
        orderBy: { title: 'asc' },
    });
};
