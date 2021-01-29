import { pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import * as TE from 'fp-ts/lib/TaskEither';
import { NextApiRequest, NextApiResponse } from 'next';
import { Err, getQueryParam, sendErrResponse, sendSuccResponse, toErr } from '../../../libs/api/apipage';
import { SpeciesSourceApi } from '../../../libs/api/apitypes';
import { sourcesBySpeciesId } from '../../../libs/db/speciessource';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    const errMsg = (): TE.TaskEither<Err, SpeciesSourceApi[]> => {
        return TE.left({ status: 400, msg: 'Failed to provide the sourceid as a query param.' });
    };

    await pipe(
        'speciesid',
        getQueryParam(req),
        O.map(parseInt),
        O.map(sourcesBySpeciesId),
        O.map(TE.mapLeft(toErr)),
        O.getOrElse(errMsg),
        TE.fold(sendErrResponse(res), sendSuccResponse(res)),
    )();
};
