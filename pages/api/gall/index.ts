import { pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import * as TE from 'fp-ts/lib/TaskEither';
import { NextApiRequest, NextApiResponse } from 'next';
import { getQueryParam, getQueryParams, sendErrResponse, sendSuccResponse, toErr } from '../../../libs/api/apipage';
import { GallApi } from '../../../libs/api/apitypes';
import { gallById, searchGalls } from '../../../libs/db/gall';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    // 2 paths:
    // 1: an ID is passed in fetch that gall
    // 2: a query string is passed in, fetch galls that start with that string

    const params = getQueryParams(req.query, ['speciesid', 'query']);

    if (params && O.isSome(params['speciesid'])) {
        const errMsg = (): TE.TaskEither<Error, GallApi[]> => {
            return TE.left(new Error('Failed to fetch the gall.'));
        };
        await pipe(
            'speciesid',
            getQueryParam(req),
            O.map(parseInt),
            O.fold(errMsg, gallById),
            TE.mapLeft(toErr),
            TE.fold(sendErrResponse(res), sendSuccResponse(res)),
        )();
    } else if (params && O.isSome(params['query'])) {
        const errMsg = (): TE.TaskEither<Error, GallApi[]> => {
            return TE.left(new Error('Failed to search for galls.'));
        };
        await pipe(
            params['query'],
            O.fold(errMsg, searchGalls),
            TE.mapLeft(toErr),
            TE.fold(sendErrResponse(res), sendSuccResponse(res)),
        )();
    } else {
        res.status(400).end('No valid query params provided. Pass either a speciesId or a query.');
    }
};
