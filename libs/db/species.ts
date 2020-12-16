import { abundance, Prisma, species } from '@prisma/client';
import { pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import * as TE from 'fp-ts/lib/TaskEither';
import { AbundanceApi, SpeciesApi } from '../api/apitypes';
import { ExtractTFromPromise, handleError, optionalWith } from '../utils/util';
import db from './db';

export const adaptAbundance = (a: abundance): AbundanceApi => ({
    ...a,
    reference: O.of(a.abundance),
});

export const abundances = (): TE.TaskEither<Error, AbundanceApi[]> => {
    const abundances = () =>
        db.abundance.findMany({
            orderBy: {
                abundance: 'asc',
            },
        });

    return pipe(
        TE.tryCatch(abundances, handleError),
        TE.map((a) => a.map(adaptAbundance)),
    );
};

export const allSpecies = (): TE.TaskEither<Error, species[]> => {
    const species = () =>
        db.species.findMany({
            orderBy: { name: 'asc' },
        });

    return TE.tryCatch(species, handleError);
};

export const speciesByName = (name: string): TE.TaskEither<Error, O.Option<species>> => {
    const species = () =>
        db.species.findFirst({
            where: {
                name: name,
            },
        });

    return pipe(TE.tryCatch(species, handleError), TE.map(O.fromNullable));
};

export const getSpecies = (
    whereClause: Prisma.speciesWhereInput[],
    operatorAnd = true,
    distinct: Prisma.SpeciesDistinctFieldEnum[] = [],
): TE.TaskEither<Error, SpeciesApi[]> => {
    const w: Prisma.speciesWhereInput = operatorAnd ? { AND: whereClause } : { OR: whereClause };

    const allSpecies = () =>
        db.species.findMany({
            include: {
                abundance: true,
                family: true,
                speciessource: { include: { source: true } },
            },
            where: w,
            distinct: distinct,
            orderBy: { name: 'asc' },
        });

    type DBSpecies = ExtractTFromPromise<ReturnType<typeof allSpecies>>;

    // we want a stronger no-null contract on what we return then is modelable in the DB
    const clean = (species: DBSpecies): SpeciesApi[] =>
        species.flatMap((s) => {
            // set the default description to make the caller's life easier
            const d = s.speciessource.find((s) => s.useasdefault === 1)?.description;
            const species: SpeciesApi = {
                ...s,
                description: O.fromNullable(d),
                taxoncode: s.taxoncode ? s.taxoncode : '',
                synonyms: O.fromNullable(s.synonyms),
                commonnames: O.fromNullable(s.commonnames),
                abundance: optionalWith(s.abundance, adaptAbundance),
                speciessource: s.speciessource.map((source) => ({
                    ...source,
                    description: O.fromNullable(source.description),
                })),
            };
            return species;
        });

    // eslint-disable-next-line prettier/prettier
    const cleaned = pipe(
        TE.tryCatch(allSpecies, handleError), 
        TE.map(clean)
    );

    return cleaned;
};
