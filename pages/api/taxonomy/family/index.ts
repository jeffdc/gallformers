import * as O from 'fp-ts/lib/Option';
import * as TE from 'fp-ts/lib/TaskEither';
import { pipe } from 'fp-ts/lib/function';
import { NextApiRequest, NextApiResponse } from 'next';
import { apiSearchEndpoint, getQueryParams, sendErrorResponse, sendSuccessResponse, toErr } from '../../../../libs/api/apipage';
import { TaxonomyEntry } from '../../../../libs/api/apitypes';
import { allFamilies, familyByName, familySearch, taxonomyEntryById } from '../../../../libs/db/taxonomy';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    // 1: an ID is passed in fetch that family
    // 2: a query string is passed in, fetch families that start with that string
    // 3: a name that will do an exact match

    const params = getQueryParams(req.query, ['familyid', 'q', 'name']);
    const errMsg = (): TE.TaskEither<Error, TaxonomyEntry[]> => {
        return TE.left(new Error('Failed to fetch the family.'));
    };

    if (params && O.isSome(params['familyid'])) {
        await pipe(
            params['familyid'],
            O.map(parseInt),
            O.fold(errMsg, taxonomyEntryById),
            TE.mapLeft(toErr),
            TE.fold(sendErrorResponse(res), sendSuccessResponse(res)),
        )();
    } else if (params && O.isSome(params['q'])) {
        apiSearchEndpoint(req, res, familySearch);
    } else if (params && O.isSome(params['name'])) {
        await pipe(
            params['name'],
            O.fold(errMsg, familyByName),
            TE.mapLeft(toErr),
            TE.fold(sendErrorResponse(res), sendSuccessResponse(res)),
        )();
    } else {
        await pipe(allFamilies(), TE.mapLeft(toErr), TE.fold(sendErrorResponse(res), sendSuccessResponse(res)))();
    }
};
