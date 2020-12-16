import { source, species } from '@prisma/client';
import { pipe } from 'fp-ts/lib/function';
import * as TE from 'fp-ts/lib/TaskEither';
import { entriesWithLinkedDefs, EntryLinked } from '../pages/glossary';
import { handleError } from '../utils/util';
import db from './db';

export type TinySpecies = {
    id: number;
    name: string;
    taxoncode: string;
};

export type TinySource = {
    id: number;
    title: string;
};

export type GlobalSearchResults = {
    species: TinySpecies[];
    glossary: EntryLinked[];
    sources: TinySource[];
};

export const globalSearch = (search: string): TE.TaskEither<Error, GlobalSearchResults> => {
    const q = `%${search}%`;

    const speciesSearch = () =>
        db.species.findMany({
            where: {
                OR: [{ name: { contains: q } }, { commonnames: { contains: q } }, { synonyms: { contains: q } }],
            },
            orderBy: { name: 'asc' },
        });

    const sourceSearch = () =>
        db.source.findMany({
            where: {
                OR: [{ author: { contains: q } }, { title: { contains: q } }],
            },
            orderBy: { title: 'asc' },
        });

    const winnowSpecies = (sp: species[]): TinySpecies[] =>
        sp.map((s) => ({
            id: s.id,
            name: s.name,
            taxoncode: s.taxoncode == null ? 'plant' : s.taxoncode,
        }));

    const winnowSource = (source: source[]): TinySource[] =>
        source.map((s) => ({
            id: s.id,
            title: s.title,
        }));

    const filterDefinitions = (entries: readonly EntryLinked[]): EntryLinked[] =>
        entries.filter((e) => e.word === search || e.definition.includes(search));

    const buildResults = (species: TinySpecies[]) => (sources: TinySource[]) => (
        glossary: EntryLinked[],
    ): GlobalSearchResults => ({
        species: species,
        glossary: glossary,
        sources: sources,
    });

    return pipe(
        TE.tryCatch(speciesSearch, handleError),
        TE.map(winnowSpecies),
        // curry the species results into the builder
        TE.map(buildResults),
        // eslint-disable-next-line prettier/prettier
        TE.map((builder) =>
            pipe(
                TE.tryCatch(sourceSearch, handleError),
                TE.map(winnowSource),
                // curry the sources into the builder
                TE.map(builder),
            ),
        ),
        TE.flatten,
        TE.map((builder) =>
            pipe(
                entriesWithLinkedDefs(),
                TE.map(filterDefinitions),
                // curry the glossary results into the builder
                TE.map(builder),
            ),
        ),
        TE.flatten,
    );
};
