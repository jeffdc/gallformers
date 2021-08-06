import * as E from 'fp-ts/lib/Either';
import { pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import * as R from 'fp-ts/lib/Record';
import * as TE from 'fp-ts/lib/TaskEither';
import { NextApiRequest, NextApiResponse } from 'next';
import { Err, getQueryParam, sendErrResponse, sendSuccResponse, toErr } from '../../../libs/api/apipage';
import { asFilterFieldType } from '../../../libs/api/apitypes';
import { deleteFilterField } from '../../../libs/db/filterfield';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
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

    if (req.method === 'DELETE') {
        await pipe(
            query,
            // eslint-disable-next-line prettier/prettier
                E.map((q) => pipe(
                    deleteFilterField(asFilterFieldType(q.fieldType), q.id),
                    TE.mapLeft(toErr),
                )),
            TE.fromEither,
            TE.flatten,
            TE.fold(sendErrResponse(res), sendSuccResponse(res)),
        )();
    }
};
