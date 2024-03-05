import * as TE from 'fp-ts/lib/TaskEither';
import { pipe } from 'fp-ts/lib/function';
import { NextApiRequest, NextApiResponse } from 'next';
import { sendErrorResponse, sendSuccessResponse, toErr } from '../../../../libs/api/apipage';
import { getSourceByTitle } from '../../../../libs/db/source';

// GET: ../source/[title]
// fetches the Source by title
//
export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    const { title } = req.query;
    if (!title || title.length <= 0) {
        res.status(400).end('Not a valid source title form.');
    } else {
        await pipe(
            getSourceByTitle(title as string),
            TE.map((t) => {
                return t[0];
            }),
            TE.mapLeft(toErr),
            TE.fold(sendErrorResponse(res), sendSuccessResponse(res)),
        )();
    }
};
