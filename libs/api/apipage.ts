import { pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import * as T from 'fp-ts/lib/Task';
import * as TA from 'fp-ts/lib/Task';
import * as TE from 'fp-ts/lib/TaskEither';
import { TaskEither } from 'fp-ts/lib/TaskEither';
import { NextApiRequest, NextApiResponse } from 'next';
import { getSession } from 'next-auth/client';
import { ParsedUrlQuery } from 'querystring';
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
    res.status(200).redirect(`/${path}${pathEnd}`).end();
};

/**
 * Function that is meant to be partially applied and passed to apiUpsertEndpoint or similar.
 * Sends the results as a JSON with status 200.
 * @param res
 */
export const onCompleteSendJson = (res: NextApiResponse, results: unknown): void => {
    res.status(200).send(JSON.stringify(results));
};

/**
 * Given a @ParsedUrlQuery try an extract a query param from it that matches the @prop name passed in.
 * @param q
 * @param prop
 * @returns an Option that contains the query value as a string if it was found.
 */
export const extractQueryParam = (q: ParsedUrlQuery, prop: string): O.Option<string> => {
    const p = q[prop];
    if (!p) return O.none;
    if (Array.isArray(p)) return O.of(p[0]);
    return O.of(p);
};

/**
 * Given a @NextApiRequest try and extract a query param from it that matches the @prop name passed in.
 * @param prop
 * @returns an Option that contains the query value as a string if it was found.
 */
export const getQueryParam = (req: NextApiRequest) => (prop: string): O.Option<string> => extractQueryParam(req.query, prop);

/**
 * Send a 200 success repsonse as JSON.
 * @param res
 * @returns we only have a return value to make it easier to compose in pipes. This function sends the requests without delay.
 */
export const sendSuccResponse = (res: NextApiResponse) => <T>(t: T): TA.Task<number> => {
    res.status(200).json(t);
    return TA.of(0); // make type checker happy
};

/**
 * Send a @status error back to the client with @e as the message, plain text.
 * @param res
 * @returns we only have a return value to make it easier to compose in pipes. This function sends the requests without delay.
 */
export const sendErrResponse = (res: NextApiResponse) => (e: Err): TA.Task<number> => {
    res.status(e.status).end(e.msg);
    console.error(e.e ? e.e : e.msg);
    return TA.of(0); // make type checker happy
};

/**
 * Type used for representing Repsonse failures back to the client.
 */
export type Err = {
    status: number;
    msg: string;
    e?: Error;
};

/**
 * Converts an @Error to an @Err type.
 * @param e
 */
export const toErr = (e: Error): Err => ({
    status: 500,
    msg: e.message,
    e: e,
});
