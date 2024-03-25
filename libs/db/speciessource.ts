import { source, species, speciessource } from '@prisma/client';
import * as A from 'fp-ts/lib/Array.js';
import * as O from 'fp-ts/lib/Option';
import * as TE from 'fp-ts/lib/TaskEither';
import { TaskEither } from 'fp-ts/lib/TaskEither';
import { pipe } from 'fp-ts/lib/function';
import { DeleteResult, SpeciesSourceApi, SpeciesSourceInsertFields } from '../api/apitypes';
import { handleError } from '../utils/util';
import db from './db';

type DBSpeciesSource = speciessource & { source: source };
const adaptor = (dbs: DBSpeciesSource[]): SpeciesSourceApi[] =>
    dbs.map((s) => ({
        ...s,
        // description: O.fromNullable(s.description),
    }));

export const speciesSourceByIds = (speciesId: string, sourceId: string): TaskEither<Error, SpeciesSourceApi[]> => {
    const source = () =>
        db.speciessource.findMany({
            include: { source: true },
            where: {
                AND: [{ species_id: { equals: parseInt(speciesId) } }, { source_id: { equals: parseInt(sourceId) } }],
            },
        });

    // eslint-disable-next-line prettier/prettier
    return pipe(
        TE.tryCatch(source, handleError),
        TE.map(adaptor),
    );
};

export const sourcesBySpecies = (id: number): TaskEither<Error, SpeciesSourceApi[]> => {
    const sources = () =>
        db.speciessource.findMany({
            where: { species_id: { equals: id } },
            include: { source: true },
        });

    return pipe(
        TE.tryCatch(sources, handleError),
        TE.map((spso) => spso.sort((a, b) => a.source.citation.localeCompare(b.source.citation))),
    );
};

export const deleteSpeciesSourceByIds = (speciesId: string, sourceId: string): TaskEither<Error, DeleteResult> => {
    const nothingToDelete = (): DeleteResult => {
        return {
            type: 'speciessource',
            name: '',
            count: 0,
        };
    };

    const toDeleteResult = (s: speciessource): DeleteResult => {
        return {
            type: 'speciessource',
            name: `mapping between speciesid: ${s?.species_id} and sourceid: ${s?.source_id}`,
            count: 1,
        };
    };

    const deleteSpeciesSource = (id: number): TaskEither<Error, DeleteResult> => {
        return pipe(
            TE.tryCatch(
                () =>
                    db.speciessource.delete({
                        where: {
                            id: id,
                        },
                    }),
                handleError,
            ),
            TE.map(toDeleteResult),
        );
    };

    // eslint-disable-next-line prettier/prettier
    return pipe(
        speciesSourceByIds(speciesId, sourceId),
        TE.map(A.lookup(0)),
        TE.map((os) => O.map((s: SpeciesSourceApi) => s.id)(os)),
        TE.map((oid) => O.fold(TE.taskify(nothingToDelete), deleteSpeciesSource)(oid)),
        TE.flatten,
    );
};

export const upsertSpeciesSource = (sourcespecies: SpeciesSourceInsertFields): TaskEither<Error, species> => {
    // if this one is the new default, then make sure all of the other ones are not default
    const setAsNewDefault = () => {
        if (sourcespecies.useasdefault) {
            return db.speciessource.updateMany({
                data: { useasdefault: 0 },
                where: {
                    species_id: { equals: sourcespecies.species },
                },
            });
        } else {
            // nothing done but we need to return the correct type
            // return Promise.resolve({ count: 0 } as Prisma.BatchPayload);
            return db.speciessource.updateMany({
                where: { id: { equals: -999 } },
                data: {},
            });
        }
    };

    const upsert = db.speciessource.upsert({
        where: {
            id: sourcespecies.id,
        },
        create: {
            source: { connect: { id: sourcespecies.source } },
            species: { connect: { id: sourcespecies.species } },
            description: sourcespecies.description,
            useasdefault: sourcespecies.useasdefault ? 1 : 0,
            externallink: sourcespecies.externallink,
        },
        update: {
            description: sourcespecies.description,
            useasdefault: sourcespecies.useasdefault ? 1 : 0,
            externallink: sourcespecies.externallink,
        },
        include: { species: true },
    });

    // eslint-disable-next-line prettier/prettier
    return pipe(
        TE.tryCatch(() => db.$transaction([setAsNewDefault(), upsert]), handleError),
        TE.map((s) => s[1]),
        TE.map((s) => s.species),
    );
};
