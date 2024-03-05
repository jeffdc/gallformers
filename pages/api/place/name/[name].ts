import * as TE from 'fp-ts/lib/TaskEither';
import { pipe } from 'fp-ts/lib/function';
import { NextApiRequest, NextApiResponse } from 'next';
import { sendErrorResponse, sendSuccessResponse, toErr } from '../../../../libs/api/apipage';
import { getPlaceByName } from '../../../../libs/db/place';

// GET: ../place/[name]
// fetches the place by name
//
export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    const { name } = req.query;
    if (!name || name.length <= 0) {
        res.status(400).end('Not a valid place name form.');
    } else {
        await pipe(
            getPlaceByName(name as string),
            TE.map((t) => {
                return t[0];
            }),
            TE.mapLeft(toErr),
            TE.fold(sendErrorResponse(res), sendSuccessResponse(res)),
        )();
    }
};
