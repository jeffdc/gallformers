import * as O from 'fp-ts/lib/Option';
import * as TE from 'fp-ts/lib/TaskEither';
import { pipe } from 'fp-ts/lib/function';
import { NextApiRequest, NextApiResponse } from 'next';
import { apiSearchEndpoint, getQueryParams, sendErrorResponse, sendSuccessResponse, toErr } from '../../../libs/api/apipage';
import { allGlossaryEntries, searchGlossary } from '../../../libs/db/glossary';

// GET: ../glossary
// fetches the glossary entries
//
export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    const params = getQueryParams(req.query, ['q']);
    if (params && O.isSome(params['q'])) {
        return await apiSearchEndpoint(req, res, searchGlossary);
    } else {
        return await pipe(allGlossaryEntries(), TE.mapLeft(toErr), TE.fold(sendErrorResponse(res), sendSuccessResponse(res)))();
    }
};
