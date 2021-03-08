import { pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import * as TE from 'fp-ts/lib/TaskEither';
import { NextApiRequest, NextApiResponse } from 'next';
import { Err, getQueryParam, sendErrResponse, sendSuccResponse, toErr } from '../../../libs/api/apipage';
import { FGS } from '../../../libs/api/taxonomy';
import { taxonomyForSpecies } from '../../../libs/db/taxonomy';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    const errMsg = (): TE.TaskEither<Err, FGS> => {
        return TE.left({ status: 400, msg: 'Failed to provide the id as a query param.' });
    };

    await pipe(
        'id',
        getQueryParam(req),
        O.map(parseInt),
        O.map(taxonomyForSpecies),
        O.map(TE.mapLeft(toErr)),
        O.getOrElse(errMsg),
        TE.fold(sendErrResponse(res), sendSuccResponse(res)),
    )();
};
