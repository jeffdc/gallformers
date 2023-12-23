import { Prisma } from '@prisma/client';
import * as TE from 'fp-ts/lib/TaskEither.js';
import { TaskEither } from 'fp-ts/lib/TaskEither.js';
import { handleError } from '../utils/util.js';
import db from './db.js';
import { pipe } from 'fp-ts/lib/function.js';

export type Stat = {
    type: string;
    count: number;
};

export const getCurrentStats = (): TaskEither<Error, Stat[]> => {
    const stats = () =>
        db.$queryRaw<Stat[]>(Prisma.sql`
            SELECT 'hosts' AS type,
                count( * ) AS count
            FROM species
            WHERE taxoncode = 'plant'
            UNION
            SELECT 'host-genera',
                count(DISTINCT t.name) 
            FROM species AS s
                INNER JOIN
                speciestaxonomy AS st ON s.id = st.species_id
                INNER JOIN
                taxonomy AS t ON t.id = st.taxonomy_id
            WHERE s.taxoncode = 'plant' AND 
                t.type = 'genus'
            UNION
            SELECT 'host-family',
                count(DISTINCT pt.name) 
            FROM species AS s
                INNER JOIN
                speciestaxonomy AS st ON s.id = st.species_id
                INNER JOIN
                taxonomy AS t ON t.id = st.taxonomy_id
                INNER JOIN
                taxonomy AS pt ON t.parent_id = pt.id
            WHERE s.taxoncode = 'plant' AND 
                pt.type = 'family'
            UNION
            SELECT 'galls',
                count( * ) 
            FROM species
            WHERE taxoncode = 'gall'
            UNION
            SELECT 'gall-genera',
                count(DISTINCT t.name) 
            FROM species AS s
                INNER JOIN
                speciestaxonomy AS st ON s.id = st.species_id
                INNER JOIN
                taxonomy AS t ON t.id = st.taxonomy_id
            WHERE s.taxoncode = 'gall' AND 
                t.type = 'genus'
            UNION
            SELECT 'gall-family',
                count(DISTINCT pt.name) 
            FROM species AS s
                INNER JOIN
                speciestaxonomy AS st ON s.id = st.species_id
                INNER JOIN
                taxonomy AS t ON t.id = st.taxonomy_id
                INNER JOIN
                taxonomy AS pt ON t.parent_id = pt.id
            WHERE s.taxoncode = 'gall' AND 
                pt.type = 'family'
            UNION
            SELECT 'sources',
                count( * ) 
            FROM source
            UNION
            SELECT 'undescribed',
                count( * )
            FROM gall
            WHERE undescribed = 1
            ;
       `);

    return pipe(
        TE.tryCatch(stats, handleError),
        // yeah Prisma screwing me over again -- they changed the raw type returned from number to bigint :(, bigint is not serializable as-is, yeah Primsa!
        // their solution, https://www.prisma.io/docs/orm/prisma-client/special-fields-and-types LOL!
        TE.map((stats) => {
            return stats.map((s) => ({
                ...s,
                count: Number(s.count),
            }));
        }),
    );
};
