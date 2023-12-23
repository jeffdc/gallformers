import * as E from 'fp-ts/lib/Either.js';
import * as O from 'fp-ts/lib/Option.js';
import * as R from 'fp-ts/lib/Record.js';
import * as TE from 'fp-ts/lib/TaskEither.js';
import { constant, pipe } from 'fp-ts/lib/function.js';
import { NextApiRequest, NextApiResponse } from 'next';
import { Err, getQueryParam, sendErrorResponse, sendSuccessResponse, toErr } from '../../../libs/api/apipage.js';
import { SpeciesSourceApi } from '../../../libs/api/apitypes.js';
import { deleteSpeciesSourceByIds, sourcesBySpecies, speciesSourceByIds } from '../../../libs/db/speciessource.js';
import { logger } from '../../../libs/utils/logger.js';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    const speciesId = getQueryParam(req)('speciesid');
    const sourceId = getQueryParam(req)('sourceid');

    if (O.isSome(speciesId) && O.isNone(sourceId)) {
        // fetch all source mappings for the species if we only have a speciesid
        await pipe(
            speciesId,
            O.map(parseInt),
            O.map(sourcesBySpecies),
            TE.fromOption(constant(new Error('Species Id changed to None! Impossible!!'))),
            TE.flatten,
            TE.mapLeft(toErr),
            TE.fold(sendErrorResponse(res), sendSuccessResponse(res)),
        )();
    } else {
        type Query = { speciesId: string; sourceId: string };

        const invalidQueryErr: Err = {
            status: 400,
            msg: 'No valid query provided. You must provide both a speciesid and a sourceid.',
        };

        const query = pipe(
            { speciesId: 'speciesid', sourceId: 'sourceid' },
            R.map(getQueryParam(req)),
            R.sequence(O.Applicative),
            O.fold(() => E.left<Err, Query>(invalidQueryErr), E.right),
        );

        const validate = (s: SpeciesSourceApi[]) => {
            if (s.length > 1) {
                const q = E.getOrElse(() => ({ speciesId: 'failed', sourceId: 'failed' }))(query);
                logger.error(`Got more than one mapping between species ${q.speciesId} and source ${q.sourceId}.`);
                return [s[0]];
            }
            return s;
        };

        if (req.method === 'GET') {
            await pipe(
                query,
                // eslint-disable-next-line prettier/prettier
                E.map((q) => pipe(
                    speciesSourceByIds(q.speciesId, q.sourceId), 
                    TE.mapLeft(toErr),
                )),                
                TE.fromEither,
                TE.flatten,
                TE.map(validate),
                TE.fold(sendErrorResponse(res), sendSuccessResponse(res)),
            )();
        } else if (req.method === 'DELETE') {
            await pipe(
                query,
                // eslint-disable-next-line prettier/prettier
                E.map((q) => pipe(
                    deleteSpeciesSourceByIds(q.speciesId, q.sourceId),
                    TE.mapLeft(toErr),
                )),
                TE.fromEither,
                TE.flatten,
                TE.fold(sendErrorResponse(res), sendSuccessResponse(res)),
            )();
        }
    }
};
