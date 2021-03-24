import { abundance, Prisma, species } from '@prisma/client';
import { pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import * as TE from 'fp-ts/lib/TaskEither';
import { AbundanceApi, SimpleSpecies, SpeciesApi, SpeciesUpsertFields } from '../api/apitypes';
import { GENUS } from '../api/taxonomy';
import { ExtractTFromPromise } from '../utils/types';
import { handleError, optionalWith } from '../utils/util';
import db from './db';
import { adaptImage } from './images';

export const updateAbundance = (id: number, abundance: string | undefined | null): Promise<number> =>
    db.$executeRaw(
        abundance == undefined || abundance == null
            ? `
            UPDATE species
            SET abundance_id = NULL
            WHERE id = ${id}
          `
            : `
            UPDATE species 
            SET abundance_id = (SELECT id FROM abundance WHERE abundance = '${abundance}')
            WHERE id = ${id}
          `,
    );

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

export const allSpeciesSimple = (): TE.TaskEither<Error, SimpleSpecies[]> =>
    pipe(
        allSpecies(),
        TE.map((s) => s.map((sp) => ({ ...sp } as SimpleSpecies))),
    );

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
    distinct: Prisma.SpeciesScalarFieldEnum[] | undefined = undefined,
): TE.TaskEither<Error, SpeciesApi[]> => {
    const w: Prisma.speciesWhereInput = operatorAnd ? { AND: whereClause } : { OR: whereClause };

    const allSpecies = () =>
        db.species.findMany({
            include: {
                abundance: true,
                speciessource: { include: { source: true } },
                image: { include: { source: { include: { speciessource: true } } } },
                taxonomy: { include: { taxonomy: true } },
                aliasspecies: { include: { alias: true } },
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
                abundance: optionalWith(s.abundance, adaptAbundance),
                images: s.image.map(adaptImage),
                aliases: s.aliasspecies.map((a) => a.alias),
                // taxonomy: s.taxonomy.map((t) => adaptTaxonomy(t.taxonomy)),
            };
            return species;
        });

    // eslint-disable-next-line prettier/prettier
    const cleaned = pipe(
        TE.tryCatch(allSpecies, handleError),
        TE.map(clean),
    );

    return cleaned;
};

export const connectOrCreateGenus = (sp: SpeciesUpsertFields): Prisma.taxonomyCreateOneWithoutTaxonomyInput => ({
    connectOrCreate: {
        where: { id: sp.fgs.genus.id },
        create: {
            description: sp.fgs.genus.description,
            name: sp.fgs.genus.name,
            type: GENUS,
            parent: { connect: { id: sp.fgs.family.id } },
        },
    },
});
