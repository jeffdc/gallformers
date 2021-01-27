import { pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import * as TE from 'fp-ts/lib/TaskEither';
import { NextApiRequest, NextApiResponse } from 'next';
import { getSession } from 'next-auth/client';
import {
    apiUpsertEndpoint,
    getQueryParam,
    onCompleteSendJson,
    sendErrResponse,
    sendSuccResponse,
    toErr,
} from '../../../libs/api/apipage';
import { ImageApi } from '../../../libs/api/apitypes';
import { getImages, updateImage } from '../../../libs/db/images';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    const session = await getSession({ req });
    if (!session) {
        res.status(401).end();
    }

    if (req.method === 'GET') {
        const errMsg = (): TE.TaskEither<Error, ImageApi[]> => {
            return TE.left(new Error('Failed to provide the species_id as a query param.'));
        };

        await pipe(
            'speciesid',
            getQueryParam(req),
            O.map(parseInt),
            O.fold(errMsg, getImages),
            TE.mapLeft(toErr),
            TE.fold(sendErrResponse(res), sendSuccResponse(res)),
        )();
    } else if (req.method === 'POST') {
        apiUpsertEndpoint(req, res, updateImage, onCompleteSendJson);
    }
};
