import * as E from 'fp-ts/Either';
import * as O from 'fp-ts/lib/Option';
import * as TE from 'fp-ts/lib/TaskEither';
import { pipe } from 'fp-ts/lib/function';
import { NextApiRequest, NextApiResponse } from 'next';
import { Err, getQueryParam, getQueryParams, sendErrorResponse, sendSuccessResponse, toErr } from '../../../../libs/api/apipage';
import { FilterField, FilterFieldTypeSchema, FilterFieldTypeValue, asFilterType } from '../../../../libs/api/apitypes';
import { getFilterFieldByNameAndType, getFilterFieldsByType } from '../../../../libs/db/filterfield';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    const params = getQueryParams(req.query, ['fieldType', 'name']);
    if (!params) {
        res.status(400).end('Invalid request.');
        return;
    }

    const endWithError = (msg: string): FilterFieldTypeValue => {
        res.status(400).end(`Invalid Request: ${msg}.`);
        return FilterFieldTypeValue.ALIGNMENTS; // never get here but keeps types inline
    };

    const fieldType = pipe(
        params['fieldType'],
        E.fromOption(() => 'Missing fieldType parameter.'),
        E.map((s) => FilterFieldTypeSchema.decode(s)),
        E.match(
            (err) => endWithError(err),
            E.match(
                (err) => endWithError(err.join(', ')),
                (v) => FilterFieldTypeValue[v as unknown as keyof typeof FilterFieldTypeValue],
            ),
        ),
    );
    const errMsg = (): TE.TaskEither<Error, FilterField[]> => {
        return TE.left(new Error('Failed to fetch the filter field.'));
    };

    if (params && O.isSome(params['name'])) {
        await pipe(
            params['name'],
            O.fold(errMsg, (n) => getFilterFieldByNameAndType(n, fieldType)),
            TE.mapLeft(toErr),
            TE.fold(sendErrorResponse(res), sendSuccessResponse(res)),
        )();
    } else {
        // fetch all for the given fieldType
        const errMsg = (q: string) => (): TE.TaskEither<Err, unknown> => {
            return TE.left({ status: 400, msg: `Failed to provide the ${q} d as a query param.` });
        };

        await pipe(
            'fieldType',
            getQueryParam(req),
            O.map(asFilterType),
            O.map(getFilterFieldsByType),
            O.map(TE.mapLeft(toErr)),
            O.getOrElse(errMsg('q')),
            TE.fold(sendErrorResponse(res), sendSuccessResponse(res)),
        )();
    }
};
