import { abundance, Prisma, PrismaPromise, species } from '@prisma/client';
import { pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import * as TE from 'fp-ts/lib/TaskEither';
import { AbundanceApi, SpeciesUpsertFields } from '../api/apitypes';
import { SimpleSpecies } from '../api/apitypes';
import { TaxonomyTypeValues } from '../api/apitypes';
import { handleError } from '../utils/util';
import db from './db';
import { connectIfNotNull } from './utils';

export const updateAbundance = (id: number, abundance: string | undefined | null): PrismaPromise<number> => {
    if (abundance == undefined || abundance == null) {
        const sql = `UPDATE species
            SET abundance_id = NULL
            WHERE id = ${id}`;
        return db.$executeRaw(Prisma.sql([sql]));
    } else {
        const sql = `UPDATE species 
            SET abundance_id = (SELECT id FROM abundance WHERE abundance = '${abundance}')
            WHERE id = ${id}`;
        return db.$executeRaw(Prisma.sql([sql]));
    }
};

export const adaptAbundance = (a: abundance): AbundanceApi => ({
    id: a.id,
    abundance: a.abundance,
    description: a.description == null ? '' : a.description,
    reference: O.of(a.abundance),
});

export const getAbundances = (): TE.TaskEither<Error, AbundanceApi[]> => {
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
        TE.map((s) => s.map((sp) => ({ ...sp }) as SimpleSpecies)),
    );

export const speciesByName = (name: string): TE.TaskEither<Error, species[]> => {
    const species = () =>
        db.species.findMany({
            where: {
                name: name,
            },
        });

    return TE.tryCatch(species, handleError);
};

export const speciesById = (id: number): TE.TaskEither<Error, species[]> => {
    const species = () =>
        db.species.findMany({
            where: {
                id: id,
            },
        });

    return TE.tryCatch(species, handleError);
};

export const connectOrCreateGenus = (sp: SpeciesUpsertFields): Prisma.taxonomyCreateNestedOneWithoutTaxonomyInput => ({
    connectOrCreate: {
        where: { id: sp.fgs.genus.id },
        create: {
            description: sp.fgs.genus.description,
            name: sp.fgs.genus.name,
            type: TaxonomyTypeValues.GENUS,
            parent: { connect: { id: sp.fgs.family.id } },
        },
    },
});

// eslint-disable-next-line @typescript-eslint/explicit-module-boundary-types
export const speciesUpdateData = (sp: SpeciesUpsertFields, isHost = true) => ({
    // more Prisma stupidity: disconnecting a record that is not connected throws. :(
    // so instead of this:
    // abundance: host.abundance
    //     ? {
    //           connect: { abundance: host.abundance },
    //       }
    //     : {
    //           disconnect: true,
    //       },
    //   we instead have to have a totally separate step in a transaction to update abundance 😠
    datacomplete: sp.datacomplete,
    name: sp.name,
    aliasspecies: {
        // typical hack, delete them all and then add
        deleteMany: { species_id: sp.id },
        create: sp.aliases.map((a) => ({
            alias: { create: { description: a.description, name: a.name, type: a.type } },
        })),
    },
    // standard pattern of delete, then re-add for Places (only for hosts since gall places are managed by gall-host mappings)
    places: isHost
        ? {
              deleteMany: { species_id: sp.id },
              create: sp.places.map((p) => ({ place_id: p.id })),
          }
        : {},
});

// eslint-disable-next-line @typescript-eslint/explicit-module-boundary-types
export const speciesCreateData = (sp: SpeciesUpsertFields) => {
    const speciesTaxonomyCreates = new Array<Prisma.speciestaxonomyCreateWithoutSpeciesInput>({
        taxonomy: {
            // the genus might be new
            connectOrCreate: {
                where: { id: sp.fgs.genus.id },
                create: {
                    description: sp.fgs.genus.description,
                    name: sp.fgs.genus.name,
                    type: TaxonomyTypeValues.GENUS,
                    parent: {
                        connect: {
                            id: sp.fgs.family.id,
                        },
                    },
                    children: {
                        create: { taxonomy_id: sp.fgs.family.id },
                    },
                },
            },
        },
    });

    // handle section for hosts
    // This is a hack to deal with the fact that a Section may not be present. Prisma craps out if you pass an empty element
    // and I can find no way to optionally connect records.
    pipe(
        sp.fgs.section,
        O.map((s) => speciesTaxonomyCreates.push({ taxonomy: { connect: { id: s.id } } })),
    );

    return {
        abundance: connectIfNotNull<Prisma.abundanceCreateNestedOneWithoutSpeciesInput, string>('abundance', sp.abundance),
        datacomplete: sp.datacomplete,
        name: sp.name,
        aliasspecies: {
            create: sp.aliases.map((a) => ({
                alias: { create: { description: a.description, name: a.name, type: a.type } },
            })),
        },
        speciestaxonomy: {
            // the speciestaxonomy records will be new since the gall is new
            // the genus and related
            create: speciesTaxonomyCreates,
        },
        places: {
            create: sp.places.map((p) => ({ place_id: p.id })),
        },
    };
};

export const speciesTaxonomyAdditionalUpdateSteps = (sp: SpeciesUpsertFields): PrismaPromise<unknown>[] => [
    // the genus could have been changed and might be new
    // delete any records that map this species to a genus that are not the same as what is inbound
    db.speciestaxonomy.deleteMany({
        where: {
            AND: [
                { species_id: sp.id },
                { taxonomy: { type: TaxonomyTypeValues.GENUS } },
                { taxonomy: { name: { not: sp.fgs.genus.name } } },
            ],
        },
    }),
    // now upsert a new species-taxonomy mapping and possibly create
    // a new Genus Taxonomy record assigning it to the known Family
    db.speciestaxonomy.upsert({
        where: { species_id_taxonomy_id: { species_id: sp.id, taxonomy_id: sp.fgs.genus.id } },
        create: {
            species: { connect: { id: sp.id } },
            taxonomy: {
                connectOrCreate: {
                    where: { id: sp.fgs.genus.id },
                    create: {
                        description: sp.fgs.genus.description,
                        name: sp.fgs.genus.name,
                        type: TaxonomyTypeValues.GENUS,
                        parent: { connect: { id: sp.fgs.family.id } },
                        children: {
                            create: {
                                taxonomy_id: sp.fgs.family.id,
                            },
                        },
                    },
                },
            },
        },
        update: {
            // no op
        },
    }),
];

export const speciesSearch = (s: string): TE.TaskEither<Error, species[]> => {
    return pipe(
        TE.tryCatch(
            () =>
                db.species.findMany({
                    where: { name: { contains: s } },
                    orderBy: { name: 'asc' },
                }),
            handleError,
        ),
    );
};
