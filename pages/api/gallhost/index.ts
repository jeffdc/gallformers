import { pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import * as TE from 'fp-ts/lib/TaskEither';
import { NextApiRequest, NextApiResponse } from 'next';
import { Err, sendErrResponse, sendSuccResponse, toErr } from '../../../libs/api/apipage';
import { SimpleSpecies } from '../../../libs/api/apitypes';
import { hostsByGallName } from '../../../libs/db/gallhost';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    const gallname = O.fromNullable(Array.isArray(req.query.gall) ? req.query.gall[0] : req.query.gall);
    const errMsg = (): TE.TaskEither<Err, SimpleSpecies[]> => {
        return TE.left({ status: 400, msg: 'Failed to provide the gall as a query param.' });
    };

    await pipe(
        gallname,
        O.map(hostsByGallName),
        O.map(TE.mapLeft(toErr)),
        O.getOrElse(errMsg),
        TE.fold(sendErrResponse(res), sendSuccResponse(res)),
    )();
};
