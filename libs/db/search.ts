import { source } from '@prisma/client';
import { pipe } from 'fp-ts/lib/function';
import * as TE from 'fp-ts/lib/TaskEither';
import { PlaceNoTreeApi } from '../api/apitypes';
import { TaxonomyEntryNoParent, TaxonomyType } from '../api/apitypes';
import { sourceToDisplay } from '../pages/renderhelpers';
import { ExtractTFromPromise } from '../utils/types';
import { handleError } from '../utils/util';
import db from './db';
import { allGlossaryEntries } from './glossary';
import { Entry } from '../api/glossary';

export type TinySpecies = {
    id: number;
    name: string;
    taxoncode: string;
    aliases: string[];
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
    const q = `${search.replaceAll(' ', '%')}`;

    const speciesSearch = () =>
        db.species.findMany({
            where: {
                OR: [{ name: { contains: q } }],
            },
            include: {
                aliasspecies: {
                    include: {
                        alias: true,
                    },
                },
            },
        });

    type SpeciesSearch = ExtractTFromPromise<ReturnType<typeof speciesSearch>>;

    const aliasSearch = () =>
        db.alias.findMany({
            include: { aliasspecies: { include: { species: true } } },
            where: { name: { contains: q } },
        });

    const mergeSpeciesAndAliases =
        (species: SpeciesSearch) =>
        (aliases: ExtractTFromPromise<ReturnType<typeof aliasSearch>>): SpeciesSearch => {
            // transpose the alias->species into species->alias
            const other = aliases
                .map((alias) =>
                    alias.aliasspecies.map((as) => ({
                        ...as.species,
                        aliasspecies: [
                            {
                                alias_id: as.alias_id,
                                species_id: as.species_id,
                                alias: { name: alias.name, description: alias.description, id: alias.id, type: alias.type },
                            },
                        ],
                    })),
                )
                .flat();

            // merge with existing species
            other.forEach((o) => {
                if (!species.find((s) => s.id === o.id)) species.push(o);
            });
            return species.sort((a, b) => a.name.localeCompare(b.name));
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
                OR: [{ name: { contains: q } }, { description: { contains: q } }],
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

    const winnowSpecies = (sp: SpeciesSearch): TinySpecies[] =>
        sp.map((s) => ({
            id: s.id,
            name: s.name,
            taxoncode: s.taxoncode == null ? 'plant' : s.taxoncode,
            aliases: s.aliasspecies.map((a) => a.alias.name),
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
