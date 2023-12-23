import { pipe } from 'fp-ts/lib/function.js';
import * as O from 'fp-ts/lib/Option.js';
import * as TE from 'fp-ts/lib/TaskEither.js';
import { NextApiRequest, NextApiResponse } from 'next';
import { Err, getQueryParam, sendErrorResponse, sendSuccessResponse, toErr } from '../../../libs/api/apipage.js';
import { SpeciesWithPlaces } from '../../../libs/api/apitypes.js';
import { hostsByGallId } from '../../../libs/db/gallhost.js';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    const errMsg = (): TE.TaskEither<Err, SpeciesWithPlaces[]> => {
        return TE.left({ status: 400, msg: 'Failed to provide the gall as a query param.' });
    };

    await pipe(
        'gallid',
        getQueryParam(req),
        O.map(parseInt),
        O.map(hostsByGallId),
        O.map(TE.mapLeft(toErr)),
        O.getOrElse(errMsg),
        TE.fold(sendErrorResponse(res), sendSuccessResponse(res)),
    )();
};
