import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import * as TE from 'fp-ts/lib/TaskEither';
import { NextApiRequest, NextApiResponse } from 'next';
import { Err, getQueryParam, getQueryParams, sendErrResponse, sendSuccResponse, toErr } from '../../../../libs/api/apipage';
import { asFilterFieldType, FilterField } from '../../../../libs/api/apitypes';
import { getFilterFieldByNameAndType, getFilterFieldsByType } from '../../../../libs/db/filterfield';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    const params = getQueryParams(req.query, ['fieldType', 'name']);
    if (!params) {
        res.status(400).end('Invalid request.');
        return;
    }

    const fieldType = asFilterFieldType(O.fold(constant(''), (ft) => ft as string)(params['fieldType']));

    const errMsg = (): TE.TaskEither<Error, FilterField[]> => {
        return TE.left(new Error('Failed to fetch the filter field.'));
    };

    if (params && O.isSome(params['name'])) {
        await pipe(
            params['name'],
            O.fold(errMsg, (n) => getFilterFieldByNameAndType(n, fieldType)),
            TE.mapLeft(toErr),
            TE.fold(sendErrResponse(res), sendSuccResponse(res)),
        )();
    } else {
        // fetch all for the given fieldType
        const errMsg = (q: string) => (): TE.TaskEither<Err, unknown> => {
            return TE.left({ status: 400, msg: `Failed to provide the ${q} d as a query param.` });
        };

        await pipe(
            'fieldType',
            getQueryParam(req),
            O.map(asFilterFieldType),
            O.map(getFilterFieldsByType),
            O.map(TE.mapLeft(toErr)),
            O.getOrElse(errMsg('q')),
            TE.fold(sendErrResponse(res), sendSuccResponse(res)),
        )();
    }
};
