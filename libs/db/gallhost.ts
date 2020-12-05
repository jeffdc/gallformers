import { host } from '@prisma/client';
import { pipe } from 'fp-ts/lib/function';
import * as TE from 'fp-ts/lib/TaskEither';
import { GallHostInsertFields } from '../api/apitypes';
import { handleError } from '../utils/util';
import db from './db';

export const insertGallHosts = (gallhost: GallHostInsertFields): TE.TaskEither<Error, host[]> => {
    const insert = () => {
        const statements = gallhost.galls
            .map((gall) => {
                return gallhost.hosts.map((host) => {
                    try {
                        return db.host.create({
                            data: {
                                gallspecies: { connect: { id: gall } },
                                hostspecies: { connect: { id: host } },
                            },
                        });
                    } catch (e) {
                        throw new AggregateError([e], `Failed to add gall-host mapping for gall(${gall}) and host(${host}).`);
                    }
                });
            })
            .flatMap((x) => x);

        return db.$transaction(statements);
    };

    // eslint-disable-next-line prettier/prettier
    return pipe(
        TE.tryCatch(insert, handleError),
    );
};
