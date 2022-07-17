import * as E from 'fp-ts/lib/Either';
import { pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import * as TE from 'fp-ts/lib/TaskEither';
import { NextApiRequest, NextApiResponse } from 'next';
import { getSession } from 'next-auth/react';
import { Err, extractQueryParam, sendErrResponse, sendSuccResponse, toErr } from '../../../libs/api/apipage';
import { IMAGES_ENDPOINT } from '../../../libs/constants';
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
            msg: `You must provide the path (bucket key) to upload to and the mime type as query params. The params you passed are: ${req.query}`,
        };

        res.setHeader('Access-Control-Allow-Origin', IMAGES_ENDPOINT);
        res.setHeader('Content-Type', 'text/plain');

        await pipe(
            extractQueryParam(req.query, 'path'),
            O.map((path) =>
                pipe(
                    extractQueryParam(req.query, 'mime'),
                    O.map((mime) => TE.tryCatch(() => getPresignedUrl(path, mime), handleError)),
                ),
            ),
            O.flatten,
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
