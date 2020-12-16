import { pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import * as TE from 'fp-ts/lib/TaskEither';
import { TaskEither } from 'fp-ts/lib/TaskEither';
import { NextApiRequest, NextApiResponse } from 'next';
import { getQueryParam, sendErrResponse, sendSuccResponse, toErr } from '../../../libs/api/apipage';
import { GallApi } from '../../../libs/api/apitypes';
import { gallById } from '../../../libs/db/gall';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    const errMsg = (): TaskEither<Error, GallApi[]> => {
        return TE.left(new Error('Failed to provide the species_id as a query param.'));
    };

    await pipe(
        'speciesid',
        getQueryParam(req),
        O.map(parseInt),
        O.fold(errMsg, gallById),
        TE.mapLeft(toErr),
        TE.fold(sendErrResponse(res), sendSuccResponse(res)),
    )();
};
