import { pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import * as TE from 'fp-ts/lib/TaskEither';
import { NextApiRequest, NextApiResponse } from 'next';
import { apiSearchEndpoint, getQueryParams, sendErrResponse, sendSuccResponse, toErr } from '../../../libs/api/apipage';
import { GallApi } from '../../../libs/api/apitypes';
import { gallById, gallByName, searchGalls } from '../../../libs/db/gall';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    // 1: an ID is passed in fetch that gall
    // 2: a query string is passed in, fetch galls that start with that string
    // 3: a name that will do an exact match

    const params = getQueryParams(req.query, ['speciesid', 'q', 'name']);
    const errMsg = (): TE.TaskEither<Error, GallApi[]> => {
        return TE.left(new Error('Failed to fetch the gall.'));
    };

    if (params && O.isSome(params['speciesid'])) {
        await pipe(
            params['speciesid'],
            O.map(parseInt),
            O.fold(errMsg, gallById),
            TE.mapLeft(toErr),
            TE.fold(sendErrResponse(res), sendSuccResponse(res)),
        )();
    } else if (params && O.isSome(params['q'])) {
        apiSearchEndpoint(req, res, searchGalls);
    } else if (params && O.isSome(params['name'])) {
        await pipe(
            params['name'],
            O.fold(errMsg, gallByName),
            TE.mapLeft(toErr),
            TE.fold(sendErrResponse(res), sendSuccResponse(res)),
        )();
    } else {
        res.status(400).end('No valid query params provided.');
    }
};
