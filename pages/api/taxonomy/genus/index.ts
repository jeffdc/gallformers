import { pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import * as TE from 'fp-ts/lib/TaskEither';
import { NextApiRequest, NextApiResponse } from 'next';
import {
    apiSearchEndpoint,
    getQueryParam,
    getQueryParams,
    sendErrResponse,
    sendSuccResponse,
    toErr,
} from '../../../../libs/api/apipage';
import { Genus } from '../../../../libs/api/taxonomy';
import { generaSearch, getGeneraForFamily } from '../../../../libs/db/taxonomy';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    // 2 query params possible:
    // 1: ?famid=X - fetch genera for a family
    // 2: ?q=X - a query string is passed in, fetch genera that contain that string
    const Q_FAMID = 'famid';

    const params = getQueryParams(req.query, [Q_FAMID, 'q']);

    if (params && O.isSome(params[Q_FAMID])) {
        const errMsg = (): TE.TaskEither<Error, Genus[]> => {
            return TE.left(new Error('Failed to fetch the genera.'));
        };
        await pipe(
            Q_FAMID,
            getQueryParam(req),
            O.map(parseInt),
            O.fold(errMsg, getGeneraForFamily),
            TE.mapLeft(toErr),
            TE.fold(sendErrResponse(res), sendSuccResponse(res)),
        )();
    } else if (params && O.isSome(params['q'])) {
        apiSearchEndpoint(req, res, generaSearch);
    } else {
        res.status(400).end('No valid query params provided. Pass either a famID or a q.');
    }
};
