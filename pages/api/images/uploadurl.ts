import * as E from 'fp-ts/lib/Either';
import { pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import * as TE from 'fp-ts/lib/TaskEither';
import { NextApiRequest, NextApiResponse } from 'next';
import { getSession } from 'next-auth/client';
import { Err, extractQueryParam, sendErrResponse, sendSuccResponse, toErr } from '../../../libs/api/apipage';
import { getPresignedUrl } from '../../../libs/images/images';
import { handleError } from '../../../libs/utils/util';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    const session = await getSession({ req });
    if (!session) {
        res.status(401).end();
    }

    if (req.method === 'GET') {
        const invalidQueryErr: Err = {
            status: 400,
            msg: 'You must provide the path (bucket key) to upload to as a query param.',
        };

        await pipe(
            extractQueryParam(req.query, 'path'),
            O.map((path) => TE.tryCatch(() => getPresignedUrl(path), handleError)),
            O.map(TE.mapLeft(toErr)),
            // eslint-disable-next-line prettier/prettier
            O.fold(
                () => E.left<Err, TE.TaskEither<Err, string>>(invalidQueryErr), 
                E.right
            ),
            TE.fromEither,
            TE.flatten,
            TE.fold(sendErrResponse(res), sendSuccResponse(res)),
        )();
    } else {
        res.status(405).end();
    }
};
