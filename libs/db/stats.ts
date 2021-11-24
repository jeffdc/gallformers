import { Prisma } from '@prisma/client';
import * as TE from 'fp-ts/lib/TaskEither';
import { TaskEither } from 'fp-ts/lib/TaskEither';
import { handleError } from '../utils/util';
import db from './db';

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

    return TE.tryCatch(stats, handleError);
};
