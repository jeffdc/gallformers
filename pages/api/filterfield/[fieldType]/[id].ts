import * as E from 'fp-ts/lib/Either';
import { constant, identity, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import * as R from 'fp-ts/lib/Record';
import * as TE from 'fp-ts/lib/TaskEither';
import { NextApiRequest, NextApiResponse } from 'next';
import { Err, getQueryParam, getQueryParams, sendErrResponse, sendSuccResponse, toErr } from '../../../../libs/api/apipage';
import { asFilterFieldType } from '../../../../libs/api/apitypes';
import { deleteFilterField, getFilterFieldByIdAndType } from '../../../../libs/db/filterfield';

// GET: ../filterfield/{filedType}/{id}
// fetches the field if it exists - returns an array, might be empty if the field does not exist
//
// DELETE ..filterfield/{fieldType}/{id}
// deletes the field
export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    if (req.method === 'DELETE') {
        type Query = { id: string; fieldType: string };

        const invalidQueryErr: Err = {
            status: 400,
            msg: 'No valid query provided. You must provide both a id and a fieldType.',
        };

        const query = pipe(
            { id: 'id', fieldType: 'fieldType' },
            R.map(getQueryParam(req)),
            R.sequence(O.Applicative),
            O.fold(() => E.left<Err, Query>(invalidQueryErr), E.right),
        );

        return await pipe(
            query,
            E.map((q) => pipe(deleteFilterField(asFilterFieldType(q.fieldType), q.id), TE.mapLeft(toErr))),
            TE.fromEither,
            TE.flatten,
            TE.fold(sendErrResponse(res), sendSuccResponse(res)),
        )();
    }

    // GET
    const params = getQueryParams(req.query, ['id', 'fieldType']);

    if (params && O.isSome(params['id']) && O.isSome(params['fieldType'])) {
        const id = O.fold<number, number>(constant(-1), identity)(O.map(parseInt)(params['id']));
        const fieldType = asFilterFieldType(O.fold<string, string>(constant(''), identity)(params['fieldType']));

        await pipe(
            getFilterFieldByIdAndType(id, fieldType),
            TE.mapLeft(toErr),
            TE.fold(sendErrResponse(res), sendSuccResponse(res)),
        )();
    } else {
        res.status(400).end('No valid query params provided.');
    }
};
