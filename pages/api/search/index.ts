import { pipe } from 'fp-ts/lib/function';
import * as E from 'fp-ts/lib/Either';
import * as O from 'fp-ts/lib/Option';
import * as R from 'fp-ts/lib/Record';
import * as TE from 'fp-ts/lib/TaskEither';
import { NextApiRequest, NextApiResponse } from 'next';
import { Err, getQueryParam, sendErrResponse, sendSuccResponse, toErr } from '../../../libs/api/apipage';
import { GallApi } from '../../../libs/api/apitypes';
import { gallsByHostGenus, gallsByHostName, gallsByHostSection } from '../../../libs/db/gall';

/**
 * The expected query params are one of:
 *
 * - host - the host name to search on
 * - genus - the genus name to search on
 * - section - the section name to search on
 */
export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    const noParamsErr = O.of(TE.left<Err, GallApi[]>({ status: 400, msg: 'No valid query params provided.' }));

    await pipe(
        { host: 'host', genus: 'genus', section: 'section' },
        R.map(getQueryParam(req)),
        R.map(O.map(decodeURI)),
        R.mapWithIndex((k, o) =>
            k === 'host' ? O.map(gallsByHostName)(o) : k === 'genus' ? O.map(gallsByHostGenus)(o) : O.map(gallsByHostSection)(o),
        ),
        R.map(O.map(TE.mapLeft(toErr))),
        R.reduce(noParamsErr, (b, a) => (O.isSome(a) ? a : b)),
        E.fromOption(() => ({ status: 500, msg: 'Failed to run search' })),
        TE.fromEither,
        TE.flatten,
        TE.fold(sendErrResponse(res), sendSuccResponse(res)),
    )();
};
