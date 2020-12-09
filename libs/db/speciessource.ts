import { Prisma, source, speciessource } from '@prisma/client';
import * as A from 'fp-ts/lib/Array';
import { pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import * as TE from 'fp-ts/lib/TaskEither';
import { TaskEither } from 'fp-ts/lib/TaskEither';
import { DeleteResult, SpeciesSourceApi, SpeciesSourceInsertFields } from '../api/apitypes';
import { handleError } from '../utils/util';
import db from './db';

type DBSpeciesSource = speciessource & { source: source };
const adaptor = (dbs: DBSpeciesSource[]): SpeciesSourceApi[] =>
    dbs.map((s) => ({
        ...s,
        description: O.fromNullable(s.description),
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

export const upsertSpeciesSource = (sourcespecies: SpeciesSourceInsertFields): TaskEither<Error, speciessource> => {
    // if this one is the new default, then make sure all of the other ones are not default
    const setAsNewDefault = () => {
        if (sourcespecies.useasdefault) {
            return db.speciessource.updateMany({
                data: { useasdefault: 0 },
                where: {
                    AND: [{ source_id: { equals: sourcespecies.source } }, { species_id: { equals: sourcespecies.species } }],
                },
            });
        } else {
            // nothing done but we need to return the correct type
            return Promise.resolve({ count: 0 } as Prisma.BatchPayload);
        }
    };

    // see if this mapping already exists
    const existing = () =>
        db.speciessource.findMany({
            where: {
                source_id: { equals: sourcespecies.source },
                species_id: { equals: sourcespecies.species },
            },
        });

    const upsert = (existingS: speciessource[]) => () =>
        db.speciessource.upsert({
            where: {
                id: existingS.length > 0 ? existingS[0].id : -1,
            },
            create: {
                source: { connect: { id: sourcespecies.source } },
                species: { connect: { id: sourcespecies.species } },
                description: sourcespecies.description,
                useasdefault: sourcespecies.useasdefault ? 1 : 0,
            },
            update: {
                description: sourcespecies.description,
                useasdefault: sourcespecies.useasdefault ? 1 : 0,
            },
        });

    // No sure elegant way to acheive this. We want setAsNewDefault to run, but we do not care about its return value for
    // further work, onl that it may have failed. If the map in the 2nd line of the pipe is not run the types will be wrong
    // in the upsert call. This is surely just my ignorance and there has to be a better way to accomplish this.
    // eslint-disable-next-line prettier/prettier
    const foo = pipe(
        TE.tryCatch(setAsNewDefault, handleError),
        TE.map(() => TE.tryCatch(existing, handleError)),
        TE.flatten,
        TE.map((s) => TE.tryCatch(upsert(s), handleError)),
        TE.flatten,
    );

    return foo;
};
