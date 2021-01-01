import * as E from 'fp-ts/lib/Either';
import { pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import * as R from 'fp-ts/lib/Record';
import * as TE from 'fp-ts/lib/TaskEither';
import { NextApiRequest, NextApiResponse } from 'next';
import { Err, getQueryParam, sendErrResponse, sendSuccResponse, toErr } from '../../../libs/api/apipage';
import { SpeciesSourceApi } from '../../../libs/api/apitypes';
import { deleteSpeciesSourceByIds, speciesSourceByIds } from '../../../libs/db/speciessource';
import { logger } from '../../../libs/utils/logger';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
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
            TE.fold(sendErrResponse(res), sendSuccResponse(res)),
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
            TE.fold(sendErrResponse(res), sendSuccResponse(res)),
        )();
    }
};
