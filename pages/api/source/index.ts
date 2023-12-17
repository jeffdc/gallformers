import { pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import * as TE from 'fp-ts/lib/TaskEither';
import { NextApiRequest, NextApiResponse } from 'next';
import { Err, getQueryParams, sendErrorResponse, sendSuccessResponse, toErr } from '../../../libs/api/apipage';
import { SourceApi, SourceWithSpeciesSourceApi } from '../../../libs/api/apitypes';
import { searchSources, sourcesWithSpeciesSourceBySpeciesId } from '../../../libs/db/source';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    // 2 paths:
    // 1: an ID is passed in fetch that source
    // 2: a query string is passed in, fetch source that contain that string

    const errMsg = (): TE.TaskEither<Err, SourceWithSpeciesSourceApi[]> => {
        return TE.left({ status: 400, msg: 'Failed to provide the speciesid as a query param.' });
    };

    const params = getQueryParams(req.query, ['speciesid', 'q']);

    if (params && O.isSome(params['speciesid'])) {
        await pipe(
            params['speciesid'],
            O.map(parseInt),
            O.map(sourcesWithSpeciesSourceBySpeciesId),
            O.map(TE.mapLeft(toErr)),
            O.getOrElse(errMsg),
            TE.fold(sendErrorResponse(res), sendSuccessResponse(res)),
        )();
    } else if (params && O.isSome(params['q'])) {
        const errMsg = (): TE.TaskEither<Error, SourceApi[]> => {
            return TE.left(new Error('Failed to search for sources.'));
        };
        await pipe(
            params['q'],
            O.fold(errMsg, searchSources),
            TE.mapLeft(toErr),
            TE.fold(sendErrorResponse(res), sendSuccessResponse(res)),
        )();
    } else {
        res.status(400).end('No valid query params provided. Pass either a speciesId or a query.');
    }
};
