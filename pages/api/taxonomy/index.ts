import * as O from 'fp-ts/lib/Option';
import * as TE from 'fp-ts/lib/TaskEither';
import { pipe } from 'fp-ts/lib/function';
import { NextApiRequest, NextApiResponse } from 'next';
import { Err, getQueryParam, sendErrorResponse, sendSuccessResponse, toErr } from '../../../libs/api/apipage';
import { taxonomyByName, taxonomyForSpecies } from '../../../libs/db/taxonomy';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    const errMsg = (q: string) => (): TE.TaskEither<Err, unknown> => {
        return TE.left({ status: 400, msg: `Failed to provide the ${q} d as a query param.` });
    };

    // seems all very kludgy - must be a better way
    const qid = pipe('id', getQueryParam(req));
    const qname = pipe('name', getQueryParam(req));

    if (O.isSome(qid)) {
        await pipe(
            qid,
            O.map(parseInt),
            O.map(taxonomyForSpecies),
            O.map(TE.mapLeft(toErr)),
            O.getOrElse(errMsg('id')),
            TE.fold(sendErrorResponse(res), sendSuccessResponse(res)),
        )();
    } else if (O.isSome(qname)) {
        await pipe(
            qname,
            O.map(taxonomyByName),
            O.map(TE.mapLeft(toErr)),
            O.getOrElse(errMsg('name')),
            TE.fold(sendErrorResponse(res), sendSuccessResponse(res)),
        )();
    }
};
