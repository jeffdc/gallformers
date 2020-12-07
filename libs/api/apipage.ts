import { pipe } from 'fp-ts/lib/function';
import * as T from 'fp-ts/lib/Task';
import * as TE from 'fp-ts/lib/TaskEither';
import { TaskEither } from 'fp-ts/lib/TaskEither';
import { NextApiRequest, NextApiResponse } from 'next';
import { getSession } from 'next-auth/client';
import { DeleteResult } from './apitypes';

/**
 *
 * @param req All of the boilerplate for an API endpoint that takes an ID as its path part.
 * @param res
 * @param fDelete
 */
export async function apiIdEndpoint(
    req: NextApiRequest,
    res: NextApiResponse,
    fDelete: (id: number) => TaskEither<Error, DeleteResult>,
): Promise<void> {
    const session = await getSession({ req });
    if (!session) {
        res.status(401).end();
    }

    if (req.method === 'DELETE') {
        const err = (e: Error) => {
            console.error(e);
            res.status(500).json({ error: 'Failed to Delete.' });
        };
        const success = (result: DeleteResult) => res.status(200).json(result);
        //TODO how to type req.query.id?
        const id = parseInt(Array.isArray(req.query.id) && req.query.id.length > 1 ? req.query.id[0] : (req.query.id as string));

        // eslint-disable-next-line prettier/prettier
            await pipe(
                fDelete(id),
                TE.fold(TE.taskify(err), TE.taskify(success)),
            )();
    } else {
        res.status(405).end();
    }
}

export async function apiUpsertEndpoint<T, R>(
    req: NextApiRequest,
    res: NextApiResponse,
    fUpsert: (item: T) => TaskEither<Error, R>,
    onComplete: (res: NextApiResponse, results: R) => void,
): Promise<void> {
    const session = await getSession({ req });
    if (!session) {
        res.status(401).end();
    }
    //TODO how to type req.body?
    const t = req.body as T;

    const err = (e: Error): T.Task<R> => {
        console.error(e);
        res.status(500).json({ error: 'Failed to Upsert.' });
        //TODO hmmm, this invovles any, must be a better way
        return T.of({} as R); // this never gets called as the above line sends a response back -- seems hacky
    };

    // eslint-disable-next-line prettier/prettier
    const r = await pipe(
        fUpsert(t), 
        TE.getOrElse(err),
    )();

    onComplete(res, r);
}

/**
 * Function that is meant to be partially applied and passed to apiUpsertEndpoint or similar.
 * Redirects (200) to the conputed path.
 * @param path the path to redirect to. The id that is later fetched will be appended
 * (N.B. no slash so you must provide it or some other separator, e.g. #).
 */
export const onCompleteRedirect = (path: string) => (res: NextApiResponse, pathEnd: unknown): void => {
    res.status(200).redirect(`${path}${pathEnd}`).end();
};

/**
 * Function that is meant to be partially applied and passed to apiUpsertEndpoint or similar.
 * Sends the results as a JSON with status 200.
 * @param res
 */
export const onCompleteSendJson = (res: NextApiResponse, results: unknown): void => {
    res.status(200).send(JSON.stringify(results));
};
