import { Prisma } from '@prisma/client';
import { pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { TaskEither } from 'fp-ts/lib/TaskEither';
import { GallApi, SearchQuery } from '../api/apitypes';
import { getGalls } from '../db/gall';

/**
 * Searches for galls based on the input SearchQuery.
 * @param query the SearchQuery to use
 * @returns a Promise<GallApi[]> with found galls, if any.
 */
export const searchGalls = (query: SearchQuery): TaskEither<Error, GallApi[]> => {
    // the locations and textures *might* come in as encoded JSON arrays so we need to parse them
    const parsearrmaybe = (maybearr: undefined | string | string[]): string[] => {
        if (maybearr == undefined) return [];
        if (!Array.isArray(maybearr)) return [maybearr];
        return JSON.parse(maybearr.toString());
    };
    query.locations = parsearrmaybe(query.locations);
    query.textures = parsearrmaybe(query.textures);

    // helper to create Where clauses
    function whereDontCare(field: O.Option<string>, toWhere: (v: string) => Prisma.gallWhereInput) {
        return pipe(
            field,
            O.map(toWhere),
            O.getOrElse(() => ({} as Prisma.gallWhereInput)),
        );
    }
    function whereDontCareArray(field: string[], o: Prisma.gallWhereInput) {
        if (field === null || field === undefined || field.length === 0) {
            return {};
        } else {
            return o;
        }
    }

    // detachable is odd case since it is Int (boolean)
    const detachableWhere: Prisma.gallWhereInput = pipe(
        query.detachable,
        O.fold(
            () => ({} as Prisma.gallWhereInput),
            (d) => ({ OR: [{ detachable: { equals: null } }, { detachable: { equals: parseInt(d) } }] }),
        ),
    );

    const data = getGalls([
        detachableWhere,
        whereDontCare(query.color, (s) => ({ color: { color: { equals: s } } })),
        whereDontCare(query.alignment, (s) => ({ alignment: { alignment: { equals: s } } })),
        whereDontCare(query.shape, (s) => ({ shape: { shape: { equals: s } } })),
        whereDontCare(query.cells, (s) => ({ cells: { cells: { equals: s } } })),
        whereDontCare(query.walls, (s) => ({ walls: { walls: { equals: s } } })),
        whereDontCareArray(query.textures, { galltexture: { some: { texture: { texture: { in: query.textures } } } } }),
        whereDontCareArray(query.locations, {
            galllocation: { some: { location: { location: { in: query.locations } } } },
        }),
        {
            hosts: {
                some: {
                    hostspecies: {
                        name: { equals: query.host },
                    },
                },
            },
        },
    ]);

    return data;
};
