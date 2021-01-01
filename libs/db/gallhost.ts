import { pipe } from 'fp-ts/lib/function';
import * as TE from 'fp-ts/lib/TaskEither';
import { GallHostUpdateFields, SimpleSpecies } from '../api/apitypes';
import { ExtractTFromPromise } from '../utils/types';
import { handleError } from '../utils/util';
import db from './db';

export const updateGallHosts = (gallhost: GallHostUpdateFields): TE.TaskEither<Error, number[]> => {
    const insert = () => {
        const deletes = db.$executeRaw(`DELETE FROM host WHERE gall_species_id = ${gallhost.gall};`);
        const values = gallhost.hosts.map((h) => `(NULL, ${gallhost.gall}, ${h})`).join(',');
        const inserts = db.$executeRaw(`INSERT INTO host (id, gall_species_id, host_species_id) VALUES ${values};`);

        return db.$transaction([deletes, inserts]);
    };

    // eslint-disable-next-line prettier/prettier
    return pipe(
        TE.tryCatch(insert, handleError),
    );
};

export const hostsByGallName = (gallname: string): TE.TaskEither<Error, SimpleSpecies[]> => {
    const lookupHosts = () =>
        db.host.findMany({
            include: { hostspecies: true },
            where: { gallspecies: { name: { equals: gallname } } },
        });

    const toSpeciesApi = (hosts: ExtractTFromPromise<ReturnType<typeof lookupHosts>>): SimpleSpecies[] =>
        hosts.flatMap((h) =>
            h.hostspecies != undefined
                ? { ...h.hostspecies, taxoncode: h.hostspecies.taxoncode ? h.hostspecies.taxoncode : '' }
                : [],
        );

    // eslint-disable-next-line prettier/prettier
    return pipe(
        TE.tryCatch(lookupHosts, handleError),
        TE.map(toSpeciesApi),
    );
};
