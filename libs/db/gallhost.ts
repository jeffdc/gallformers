import { Prisma, PrismaPromise } from '@prisma/client';
import { pipe } from 'fp-ts/lib/function';
import * as TE from 'fp-ts/lib/TaskEither';
import { GallApi, GallHostUpdateFields, SpeciesWithPlaces } from '../api/apitypes';
import { ExtractTFromPromise } from '../utils/types';
import { handleError } from '../utils/util';
import db from './db';
import { gallByIdAsO } from './gall';

const toValues = (gallid: number, hostids: number[]) => hostids.map((h) => `(NULL, ${gallid}, ${h})`).join(',');

const toInsertStatement = (gallid: number, hostids: number[]): PrismaPromise<number> => {
    const sql = `INSERT INTO host (id, gall_species_id, host_species_id) VALUES ${toValues(gallid, hostids)};`;
    return db.$executeRaw(Prisma.sql([sql]));
};

export const updateGallHosts = (gallhost: GallHostUpdateFields): TE.TaskEither<Error, GallApi> => {
    const doTx = () => () => {
        const sql = `DELETE FROM host WHERE gall_species_id = ${gallhost.gall};`;
        const deletes = db.$executeRaw(Prisma.sql([sql]));
        const hosts = [...new Set([...gallhost.hosts])];

        const steps = [deletes];
        if (hosts.length > 0) steps.push(toInsertStatement(gallhost.gall, hosts));

        // handle the gall range - for now hack using the existing table
        steps.push(db.$executeRaw(Prisma.sql([`DELETE FROM speciesplace WHERE species_id = ${gallhost.gall}`])));
        gallhost.rangeExclusions.forEach((place) =>
            steps.push(
                db.$executeRaw(
                    Prisma.sql([`INSERT INTO speciesplace (species_id, place_id) VALUES (${gallhost.gall}, ${place.id})`]),
                ),
            ),
        );

        return db.$transaction(steps);
    };

    return pipe(
        TE.tryCatch(doTx(), handleError),
        TE.chain(() => gallByIdAsO(gallhost.gall)),
        TE.map(TE.fromOption(() => new Error('Failed to retrieve gall after GallHost update.'))),
        TE.flatten,
    );
};

export const hostsByGallId = (gallid: number): TE.TaskEither<Error, SpeciesWithPlaces[]> => {
    const lookupHosts = () =>
        db.host.findMany({
            include: { hostspecies: { include: { places: { include: { place: true } } } } },
            where: { gall_species_id: gallid },
        });

    const toSpeciesApi = (hosts: ExtractTFromPromise<ReturnType<typeof lookupHosts>>): SpeciesWithPlaces[] =>
        hosts.flatMap((h) =>
            h.hostspecies != undefined
                ? {
                      ...h.hostspecies,
                      taxoncode: h.hostspecies.taxoncode ? h.hostspecies.taxoncode : '',
                      places: h.hostspecies.places.map((p) => p.place),
                  }
                : [],
        );

    // eslint-disable-next-line prettier/prettier
    return pipe(
        TE.tryCatch(lookupHosts, handleError),
        TE.map(toSpeciesApi),
    );
};
