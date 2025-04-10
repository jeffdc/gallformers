import * as E from 'fp-ts/lib/Either';
import * as O from 'fp-ts/lib/Option';
import * as TE from 'fp-ts/lib/TaskEither';
import { pipe } from 'fp-ts/lib/function';
import { NextApiRequest, NextApiResponse } from 'next';
import {
    Err,
    apiUpsertEndpoint,
    getQueryParam,
    onCompleteSendJson,
    sendErrorResponse,
    sendSuccessResponse,
    toErr,
} from '../../../libs/api/apipage';

import { deleteImages, getImages, updateImage } from '../../../libs/db/images';
import { csvAsNumberArr } from '../../../libs/utils/util';
import { getServerSession } from 'next-auth';
import authOptions from '../../../pages/api/auth/[...nextauth]';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    // eslint-disable-next-line @typescript-eslint/no-unsafe-argument
    const session = await getServerSession(req, res, authOptions);
    if (!session) {
        res.status(401).end();
    }
    const errMsg =
        (msg: string) =>
        <T,>(): TE.TaskEither<Error, T> => {
            return TE.left(new Error(msg));
        };

    if (req.method === 'GET') {
        await pipe(
            'speciesid',
            getQueryParam(req),
            O.map(parseInt),
            O.fold(errMsg('Failed to provide the speciesid as a query param.'), getImages),
            TE.mapLeft(toErr),
            TE.fold(sendErrorResponse(res), sendSuccessResponse(res)),
        )();
    } else if (req.method === 'POST') {
        await apiUpsertEndpoint(req, res, updateImage, onCompleteSendJson);
    } else if (req.method === 'DELETE') {
        const invalidQueryErr: Err = {
            status: 400,
            msg: `You must provide the speciesid and an array of imageids to delete as query params. The params you passed are: ${JSON.stringify(req.query)}`,
        };

        await pipe(
            'speciesid',
            getQueryParam(req),
            O.map(parseInt),

            O.map((spId) => pipe('imageids', getQueryParam(req), O.map(csvAsNumberArr), O.map(deleteImages(spId)))),
            O.flatten,
            O.map(TE.mapLeft(toErr)),

            O.fold(() => E.left<Err, TE.TaskEither<Err, number>>(invalidQueryErr), E.right),
            TE.fromEither,
            TE.flatten,
            TE.fold(sendErrorResponse(res), sendSuccessResponse(res)),
        )();
    } else {
        res.status(405).end();
    }
};
