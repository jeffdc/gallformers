import { source, species } from '@prisma/client';
import { pipe } from 'fp-ts/lib/function';
import * as TE from 'fp-ts/lib/TaskEither';
import { PlaceNoTreeApi } from '../api/apitypes';
import { TaxonomyEntryNoParent, TaxonomyType } from '../api/taxonomy';
import { sourceToDisplay } from '../pages/renderhelpers';
import { ExtractTFromPromise } from '../utils/types';
import { handleError } from '../utils/util';
import db from './db';
import { allGlossaryEntries, Entry } from './glossary';

export type TinySpecies = {
    id: number;
    name: string;
    taxoncode: string;
};

export type TinySource = {
    id: number;
    source: string;
};

export type GlobalSearchResults = {
    species: TinySpecies[];
    glossary: Entry[];
    sources: TinySource[];
    taxa: TaxonomyEntryNoParent[];
    places: PlaceNoTreeApi[];
};

export const globalSearch = (search: string): TE.TaskEither<Error, GlobalSearchResults> => {
    const q = `%${search}%`;

    const speciesSearch = () =>
        db.species.findMany({
            where: {
                OR: { name: { contains: q } },
            },
        });

    const aliasSearch = () =>
        db.alias.findMany({
            include: { aliasspecies: { include: { species: true } } },
            where: { name: { contains: q } },
        });

    const mergeSpeciesAndAliases =
        (s: species[]) =>
        (a: ExtractTFromPromise<ReturnType<typeof aliasSearch>>): species[] => {
            const other = a.map((aa) => aa.aliasspecies.map((as) => as.species)).flat();
            other.forEach((o) => {
                if (!s.find((s) => s.id === o.id)) s.push(o);
            });
            return s.sort((a, b) => a.name.localeCompare(b.name));
        };

    const sourceSearch = () =>
        db.source.findMany({
            where: {
                OR: [{ author: { contains: q } }, { title: { contains: q } }],
            },
            orderBy: { title: 'asc' },
        });

    const taxaSearch = () =>
        db.taxonomy.findMany({
            where: {
                name: { contains: q },
            },
            select: {
                id: true,
                name: true,
                description: true,
                type: true,
            },
        });

    const placeSearch = () =>
        db.place.findMany({
            where: {
                OR: [{ name: { contains: q } }, { code: { contains: q } }],
            },
            orderBy: { name: 'asc' },
        });

    const winnowTaxa = (taxa: ExtractTFromPromise<ReturnType<typeof taxaSearch>>): TaxonomyEntryNoParent[] =>
        taxa.map((t) => ({
            ...t,
            description: t.description ?? '',
            type: t.type as TaxonomyType,
        }));

    const winnowSpecies = (sp: species[]): TinySpecies[] =>
        sp.map((s) => ({
            id: s.id,
            name: s.name,
            taxoncode: s.taxoncode == null ? 'plant' : s.taxoncode,
        }));

    const winnowSource = (source: source[]): TinySource[] =>
        source.map((s) => ({
            id: s.id,
            source: sourceToDisplay(s),
        }));

    const filterDefinitions = (entries: readonly Entry[]): Entry[] =>
        entries.filter((e) => e.word === search || e.definition.includes(search));

    const buildResults =
        (species: TinySpecies[]) =>
        (sources: TinySource[]) =>
        (glossary: Entry[]) =>
        (places: PlaceNoTreeApi[]) =>
        (taxa: TaxonomyEntryNoParent[]): GlobalSearchResults => ({
            species: species,
            glossary: glossary,
            sources: sources,
            taxa: taxa,
            places: places,
        });

    return pipe(
        TE.tryCatch(speciesSearch, handleError),
        // eslint-disable-next-line prettier/prettier
        TE.map((sp) =>
            pipe(
                TE.tryCatch(aliasSearch, handleError),
                TE.map(mergeSpeciesAndAliases(sp)),
            )
        ),
        TE.flatten,
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
                allGlossaryEntries(),
                TE.map(filterDefinitions),
                // curry the glossary results into the builder
                TE.map(builder),
            ),
        ),
        TE.flatten,
        TE.map((builder) =>
            pipe(
                TE.tryCatch(placeSearch, handleError),
                // curry the place results into the builder
                TE.map(builder),
            ),
        ),
        TE.flatten,
        TE.map((builder) =>
            pipe(
                TE.tryCatch(taxaSearch, handleError),
                TE.map(winnowTaxa),
                TE.map((x) => x),
                TE.map(builder),
            ),
        ),
        TE.flatten,
    );
};
