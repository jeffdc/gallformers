import { place, Prisma } from '@prisma/client';
import { pipe } from 'fp-ts/lib/function.js';
import * as TE from 'fp-ts/lib/TaskEither.js';
import { TaskEither } from 'fp-ts/lib/TaskEither.js';
import { DeleteResult, PlaceApi, PlaceNoTreeApi, PlaceNoTreeUpsertFields, PlaceWithHostsApi } from '../api/apitypes.js';
import { ExtractTFromPromise } from '../utils/types.js';
import { handleError } from '../utils/util.js';
import db from './db.js';

/**
 * Fetch all the ids for the places.
 * @returns
 */
export const allPlaceIds = (): TaskEither<Error, string[]> => {
    const places = () =>
        db.place.findMany({
            select: { id: true },
        });

    return pipe(
        TE.tryCatch(places, handleError),
        TE.map((places) => places.map((p) => p.id.toString())),
    );
};

/**
 * A general way to fetch places. Check this file for pre-defined helpers that are easier to use.
 * @param whereClause a where clause by which to filter places - defaults to returning only states and provinces
 */
export const getPlaces = (
    whereClause: Prisma.placeWhereInput = { type: { in: ['state', 'province'] } },
    distinct: Prisma.PlaceScalarFieldEnum[] = ['id'],
): TaskEither<Error, PlaceApi[]> => {
    const places = () =>
        db.place.findMany({
            include: {
                children: { include: { child: true, parent: true } },
                parent: { include: { child: true, parent: true } },
            },
            where: whereClause,
            distinct: distinct,
            orderBy: { name: 'asc' },
        });

    type DBPlace = ExtractTFromPromise<ReturnType<typeof places>>;

    // this is a mess and confusing. the way Prisma handles these relationships is baffling.
    const localAdaptor = (places: DBPlace): PlaceApi[] =>
        places.map((p) => ({
            ...p,
            children: p.parent.map((pp) => ({
                ...pp.child,
                parent: [],
                children: [],
            })),
            parent: p.children.map((pp) => ({
                ...pp.parent,
                parent: [],
                children: [],
            })),
        }));

    return pipe(TE.tryCatch(places, handleError), TE.map(localAdaptor));
};

export const searchPlaces = (s: string): TaskEither<Error, PlaceNoTreeApi[]> => {
    return pipe(
        getPlaces({ name: { contains: s } }),
        TE.map((p) => p.map((pp) => ({ ...pp }))),
    );
};

export const placeById = (id: number): TaskEither<Error, PlaceWithHostsApi[]> => {
    const places = () =>
        db.place.findMany({
            include: {
                children: { include: { child: true, parent: true } },
                parent: { include: { child: true, parent: true } },
                species: { include: { species: { include: { aliasspecies: { include: { alias: true } } } } } },
            },
            where: { id: id },
            distinct: ['id'],
            orderBy: { name: 'asc' },
        });

    type DBPlace = ExtractTFromPromise<ReturnType<typeof places>>;

    // this is a mess and confusing. the way Prisma handles these relationships is baffling.
    const adaptor = (places: DBPlace): PlaceWithHostsApi[] =>
        places.map((p) => ({
            ...p,
            children: p.parent.map((pp) => ({
                ...pp.child,
                parent: [],
                children: [],
            })),
            parent: p.children.map((pp) => ({
                ...pp.parent,
                parent: [],
                children: [],
            })),
            // no need to assign the places to the host since we are fetching a place with hosts
            hosts: p.species.map((s) => ({ ...s.species, aliases: s.species.aliasspecies.map((a) => a.alias), places: [] })),
        }));

    return pipe(TE.tryCatch(places, handleError), TE.map(adaptor));
};

export const deletePlace = (id: number): TaskEither<Error, DeleteResult> => {
    const results = () => {
        // since Prisma does not yet handle cascade deletion
        const sql = `DELETE FROM place WHERE id = ${id}`;
        return db.$executeRaw(Prisma.sql([sql]));
    };

    const toDeleteResult = (result: number): DeleteResult => {
        return {
            type: 'place',
            name: '',
            count: result,
        };
    };
    // eslint-disable-next-line prettier/prettier
    return pipe(
        TE.tryCatch(results, handleError),
        TE.map(toDeleteResult),
    );
};

export const upsertPlace = (place: PlaceNoTreeUpsertFields): TaskEither<Error, PlaceNoTreeApi> => {
    const adaptorPlaceNoTreeApi = (p: place): PlaceNoTreeApi => ({
        ...p,
    });

    const upsert = () =>
        db.place.upsert({
            where: { id: place.id },
            update: {
                name: place.name,
                code: place.code,
                type: place.type,
            },
            create: {
                name: place.name,
                code: place.code,
                type: place.type,
            },
        });

    // eslint-disable-next-line prettier/prettier
    return pipe(
        TE.tryCatch(upsert, handleError),
        TE.map(adaptorPlaceNoTreeApi),
    );
};
