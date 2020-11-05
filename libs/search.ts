import { GallDistinctFieldEnum, gallWhereInput, PrismaClient } from "@prisma/client";
import { Gall, SearchQuery } from "./types";

/**
 * Searches for galls based on the input SearchQuery.
 * @param query the SearchQuery to use
 * @returns a Promise<Gall[]> with found galls, if any. 
 */
export const searchGalls = async (query: SearchQuery): Promise<Gall[]> => {
     // Useful for logging SQL that is generated for debugging the search
    // const newdb = new PrismaClient({log: ['query']}); 
    const newdb = new PrismaClient();

    console.log(`Searching for galls with '${JSON.stringify(query, null, '  ')}'`);

    // the locations and textures *might* come in as encoded JSON arrays so we need to parse them
    const parsearrmaybe = (maybearr: undefined | string | string[]): string[] => {
        if (maybearr == undefined) return []
        if (!Array.isArray(maybearr)) return [maybearr]
        return JSON.parse(maybearr.toString())
    }
    query.locations = parsearrmaybe(query.locations);
    query.textures = parsearrmaybe(query.textures);

    // helper to create Where clauses
    function whereDontCare(field: string | string[] | undefined, o: gallWhereInput) {
        if (field === null || field === undefined || field === '' || (Array.isArray(field) && field.length === 0)) {
            return {}
        } else {
            return o
        }
    }
    // detachable is odd case since it is Int (boolean)
    const detachableWhere =  
        (query.detachable !== '0' && query.detachable !== '1') ?
            {}
        :
            { OR: [ {detachable: { equals: null }}, {detachable: { equals: parseInt(query.detachable) }} ] };

    const data: Promise<Gall[]> = newdb.gall.findMany({
        include: {
            alignment: {},
            cells: {},
            color: {},
            galllocation: {
                include: { location: {} }
            },
            shape: {},
            species: {
                include: {
                    hosts: true,
                }
            },
            galltexture: {
                include: { texture: {} }
            },
            walls: {},
        },
        where: {
            AND: [
                detachableWhere,
                whereDontCare(query.color, { color: { color: { equals: query.color } } }),
                whereDontCare(query.alignment, { alignment: { alignment: { equals: query.alignment } } }),
                whereDontCare(query.shape, { shape: { shape: { equals: query.shape } } }),
                whereDontCare(query.cells, { cells: { cells: { equals: query.cells } } }),
                whereDontCare(query.walls, { walls: { walls: { equals: query.walls } } }),
                whereDontCare(query.textures, { galltexture: { some: { texture: { texture: { in: query.textures } } } } }),
                whereDontCare(query.locations, { galllocation: { some: { location: { location: { in: query.locations } } } } }),
                {
                    species: {
                        hosts: {
                            some: {
                                hostspecies: {
                                    name: { equals: query.host }
                                }
                            }
                        }
                    }                            
                },
            ]
        },
        distinct: [GallDistinctFieldEnum.species_id],
    }).then( d => {
        // due to a limitation in Prisma it is not possible to sort on a related field, so we have to sort now
        d.sort((g1,g2) => {
            if (g1.species.name < g2.species.name) return -1
            if (g1.species.name > g2.species.name) return 1
            return 0
        })
        return d
    });

    return data
}