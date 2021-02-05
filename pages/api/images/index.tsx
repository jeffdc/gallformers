import { pipe } from 'fp-ts/lib/function';
import * as E from 'fp-ts/lib/Either';
import * as O from 'fp-ts/lib/Option';
import * as TE from 'fp-ts/lib/TaskEither';
import { NextApiRequest, NextApiResponse } from 'next';
import { getSession } from 'next-auth/client';
import {
    apiUpsertEndpoint,
    Err,
    getQueryParam,
    onCompleteSendJson,
    sendErrResponse,
    sendSuccResponse,
    toErr,
} from '../../../libs/api/apipage';

import { deleteImages, getImages, updateImage } from '../../../libs/db/images';
import { csvAsNumberArr } from '../../../libs/utils/util';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    const session = await getSession({ req });
    if (!session) {
        res.status(401).end();
    }
    const errMsg = (msg: string) => <T extends unknown>(): TE.TaskEither<Error, T> => {
        return TE.left(new Error(msg));
    };

    if (req.method === 'GET') {
        await pipe(
            'speciesid',
            getQueryParam(req),
            O.map(parseInt),
            O.fold(errMsg('Failed to provide the speciesid as a query param.'), getImages),
            TE.mapLeft(toErr),
            TE.fold(sendErrResponse(res), sendSuccResponse(res)),
        )();
    } else if (req.method === 'POST') {
        await apiUpsertEndpoint(req, res, updateImage, onCompleteSendJson);
    } else if (req.method === 'DELETE') {
        const invalidQueryErr: Err = {
            status: 400,
            msg: `You must provide the speciesid and an array of imageids to delete as query params. The params you passed are: ${req.query}`,
        };

        await pipe(
            'speciesid',
            getQueryParam(req),
            O.map(parseInt),
            // eslint-disable-next-line prettier/prettier
            O.map((spid) =>
                pipe(
                    'imageids',
                    getQueryParam(req),
                    O.map(csvAsNumberArr),
                    O.map(deleteImages(spid)),
                ),
            ),
            O.flatten,
            O.map(TE.mapLeft(toErr)),
            // eslint-disable-next-line prettier/prettier
            O.fold(
                () => E.left<Err, TE.TaskEither<Err, number>>(invalidQueryErr), 
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
