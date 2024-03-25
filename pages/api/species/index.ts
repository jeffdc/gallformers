import { species } from '@prisma/client';
import { pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import * as TE from 'fp-ts/lib/TaskEither';
import { NextApiRequest, NextApiResponse } from 'next';
import { apiSearchEndpoint, getQueryParams, sendErrorResponse, sendSuccessResponse, toErr } from '../../../libs/api/apipage';
import { speciesById, speciesByName, speciesSearch } from '../../../libs/db/species';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    // 1: an ID is passed in fetch that species
    // 2: a query string is passed in, fetch galls that start with that string
    // 3: a name that will do an exact match
    const params = getQueryParams(req.query, ['speciesid', 'q', 'name']);
    const errMsg = (): TE.TaskEither<Error, species[]> => {
        return TE.left(new Error('Failed to fetch the species.'));
    };

    if (params && O.isSome(params['speciesid'])) {
        await pipe(
            params['speciesid'],
            O.map(parseInt),
            O.fold(errMsg, speciesById),
            TE.mapLeft(toErr),
            TE.fold(sendErrorResponse(res), sendSuccessResponse(res)),
        )();
    } else if (params && O.isSome(params['q'])) {
        await apiSearchEndpoint(req, res, speciesSearch);
    } else if (params && O.isSome(params['name'])) {
        await pipe(
            params['name'],
            O.fold(errMsg, speciesByName),
            TE.mapLeft(toErr),
            TE.fold(sendErrorResponse(res), sendSuccessResponse(res)),
        )();
    } else {
        res.status(400).end('No valid query params provided.');
    }
};
