import { pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import * as TE from 'fp-ts/lib/TaskEither';
import { NextApiRequest, NextApiResponse } from 'next';
import { apiSearchEndpoint, getQueryParams, sendErrorResponse, sendSuccessResponse, toErr } from '../../../../libs/api/apipage';
import { SectionApi } from '../../../../libs/api/apitypes';
import { allSections, sectionById, sectionByName, sectionSearch } from '../../../../libs/db/taxonomy';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    // 1: an ID is passed in fetch that section
    // 2: a query string is passed in, fetch sections that start with that string
    // 3: a name that will do an exact match

    const params = getQueryParams(req.query, ['sectionid', 'q', 'name']);
    const errMsg = (): TE.TaskEither<Error, SectionApi[]> => {
        return TE.left(new Error('Failed to fetch the family.'));
    };

    if (params && O.isSome(params['sectionid'])) {
        await pipe(
            params['sectionid'],
            O.map(parseInt),
            O.fold(errMsg, sectionById),
            TE.mapLeft(toErr),
            TE.fold(sendErrorResponse(res), sendSuccessResponse(res)),
        )();
    } else if (params && O.isSome(params['q'])) {
        apiSearchEndpoint(req, res, sectionSearch);
    } else if (params && O.isSome(params['name'])) {
        await pipe(
            params['name'],
            O.fold(errMsg, sectionByName),
            TE.mapLeft(toErr),
            TE.fold(sendErrorResponse(res), sendSuccessResponse(res)),
        )();
    } else {
        await pipe(allSections(), TE.mapLeft(toErr), TE.fold(sendErrorResponse(res), sendSuccessResponse(res)))();
    }
};
