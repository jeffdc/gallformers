import { Prisma } from '@prisma/client';
import { TaskEither } from 'fp-ts/lib/TaskEither';
import { GallApi, SearchQuery } from '../api/apitypes';
import { getGalls } from '../db/gall';

/**
 * Searches for galls based on the input SearchQuery.
 * @param query the SearchQuery to use
 * @returns a Promise<GallApi[]> with found galls, if any.
 */
export const searchGalls = (query: SearchQuery): TaskEither<Error, GallApi[]> => {
    console.log(`Searching for galls with '${JSON.stringify(query, null, '  ')}'`);

    // the locations and textures *might* come in as encoded JSON arrays so we need to parse them
    const parsearrmaybe = (maybearr: undefined | string | string[]): string[] => {
        if (maybearr == undefined) return [];
        if (!Array.isArray(maybearr)) return [maybearr];
        return JSON.parse(maybearr.toString());
    };
    query.locations = parsearrmaybe(query.locations);
    query.textures = parsearrmaybe(query.textures);

    // helper to create Where clauses
    function whereDontCare(field: string | string[] | undefined, o: Prisma.gallWhereInput) {
        if (field === null || field === undefined || field === '' || (Array.isArray(field) && field.length === 0)) {
            return {};
        } else {
            return o;
        }
    }
    // detachable is odd case since it is Int (boolean)
    const detachableWhere =
        query.detachable !== '0' && query.detachable !== '1'
            ? {}
            : { OR: [{ detachable: { equals: null } }, { detachable: { equals: parseInt(query.detachable) } }] };

    const data = getGalls([
        detachableWhere,
        whereDontCare(query.color, { color: { color: { equals: query.color } } }),
        whereDontCare(query.alignment, { alignment: { alignment: { equals: query.alignment } } }),
        whereDontCare(query.shape, { shape: { shape: { equals: query.shape } } }),
        whereDontCare(query.cells, { cells: { cells: { equals: query.cells } } }),
        whereDontCare(query.walls, { walls: { walls: { equals: query.walls } } }),
        whereDontCare(query.textures, { galltexture: { some: { texture: { texture: { in: query.textures } } } } }),
        whereDontCare(query.locations, {
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
