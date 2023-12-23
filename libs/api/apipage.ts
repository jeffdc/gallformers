import * as E from 'fp-ts/lib/Either.js';
import * as O from 'fp-ts/lib/Option.js';
import * as TA from 'fp-ts/lib/Task.js';
import * as TE from 'fp-ts/lib/TaskEither.js';
import { pipe } from 'fp-ts/lib/function.js';
import { NextApiRequest, NextApiResponse } from 'next';
import { getSession } from 'next-auth/react';
import { ParsedUrlQuery } from 'querystring';
import { logger } from '../utils/logger.js';
import { DeleteResult } from './apitypes.js';

/**
 *
 * @param req All of the boilerplate for an API endpoint that takes an ID as its path part.
 * @param res
 * @param fDelete
 */
export async function apiIdEndpoint<T>(
    req: NextApiRequest,
    res: NextApiResponse,
    fDelete: ((id: number) => TE.TaskEither<Error, DeleteResult>) | undefined = undefined,
    fGet: ((id: number) => TE.TaskEither<Error, T>) | undefined = undefined,
): Promise<void> {
    const session = await getSession({ req });
    if (!session) {
        res.status(401).end();
    }

    const invalidQueryErr: Err = {
        status: 400,
        msg: `No valid query provided. You must provide an id value to ${req.method}.`,
    };

    const runRequest = <T>(f: (id: number) => TE.TaskEither<Error, T>): Promise<never> =>
        pipe(
            extractQueryParam(req.query, 'id'),
            O.map(parseInt),
            O.map<number, TE.TaskEither<Error, T>>(f),
            O.map(TE.mapLeft(toErr)),
            // eslint-disable-next-line prettier/prettier
            O.fold(
                () => E.left<Err, TE.TaskEither<Err, T>>(invalidQueryErr),
                E.right
            ),
            TE.fromEither,
            TE.flatten,
            TE.fold(sendErrorResponse(res), sendSuccessResponse(res)),
        )();

    if (req.method === 'GET' && fGet != undefined) {
        await runRequest(fGet);
    } else if (req.method === 'DELETE' && fDelete != undefined) {
        await runRequest(fDelete);
    } else {
        res.status(405).end();
    }
}

export async function apiUpsertEndpoint<T, R>(
    req: NextApiRequest,
    res: NextApiResponse,
    fUpsert: (item: T) => TE.TaskEither<Error, R>,
    onComplete: (res: NextApiResponse) => (results: R) => TA.Task<never>,
): Promise<void> {
    const session = await getSession({ req });
    if (!session) {
        res.status(401).end();
    }

    const invalidQueryErr: Err = {
        status: 400,
        msg: 'Can not upsert. No valid item provided in request body.',
    };

    //JDC: added this to try and help figure out what is causing the weird crash that Chris triggers
    // logger.info(req, 'Upsert request');
    // logger.info(req.body, 'Upsert request body');

    //TODO - figure out how to make this type safe. Maybe need to have caller pass conversion f?
    const t = !req.body ? O.none : O.of(req.body as T);

    await pipe(
        t,
        O.map(fUpsert),
        // if the upsert failed for any reason convert the Err for downstream processing
        O.map(TE.mapLeft(toErr)),
        // if the Option is None then the original request was bad
        // eslint-disable-next-line prettier/prettier
        O.fold(
            () => E.left<Err, TE.TaskEither<Err, R>>(invalidQueryErr), 
            E.right
        ),
        TE.fromEither,
        TE.flatten,
        //JDC: added this to try and help figure out what is causing the weird crash that Chris triggers
        TE.mapLeft((e) => {
            logger.error(e, 'Failed doing upsert.');
            return e;
        }),
        TE.fold(sendErrorResponse(res), onComplete(res)),
    )();
}

export async function apiSearchEndpoint<T>(
    req: NextApiRequest,
    res: NextApiResponse,
    dbSearch: (s: string) => TE.TaskEither<Error, T[]>,
) {
    const errMsg = (q: string) => (): TE.TaskEither<Err, unknown> => {
        return TE.left({ status: 400, msg: `Failed to provide the ${q} d as a query param.` });
    };

    return await pipe(
        'q',
        getQueryParam(req),
        O.map(dbSearch),
        O.map(TE.mapLeft(toErr)),
        O.getOrElse(errMsg('q')),
        TE.fold(sendErrorResponse(res), sendSuccessResponse(res)),
    )();
}

/**
 * Function that is meant to be partially applied and passed to apiUpsertEndpoint or similar.
 * Redirects (200) to the computed path.
 * @param path the path to redirect to. The id that is later fetched will be appended
 * (N.B. no slash so you must provide it or some other separator, e.g. #).
 */
export const onCompleteRedirect =
    (path: string) =>
    (res: NextApiResponse) =>
    (pathEnd: unknown): TA.Task<never> => {
        res.status(200).redirect(`/${path}${pathEnd}`).end();
        return TA.never;
    };

/**
 * Function that is meant to be partially applied and passed to apiUpsertEndpoint or similar.
 * Sends the results as a JSON with status 200.
 * @param res
 */
export const onCompleteSendJson =
    (res: NextApiResponse) =>
    (results: unknown): TA.Task<never> => {
        res.status(200).send(JSON.stringify(results));
        return TA.never;
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
 * Given a @ParsedUrlQuery try and extract all of the named params that match the passed in @params.
 * @param q
 * @param params
 * @returns an Object where the param is the key and an Option<string> is the value
 */
export const getQueryParams = (q: ParsedUrlQuery | undefined, params: string[]): Record<string, O.Option<string>> | undefined => {
    if (q == undefined) return undefined;

    return params.reduce((acc, p) => ({ ...acc, [p]: extractQueryParam(q, p) }), {} as Record<string, O.Option<string>>);
};

/**
 * Given a @NextApiRequest try and extract a query param from it that matches the @prop name passed in.
 * @param prop
 * @returns an Option that contains the query value as a string if it was found.
 */
export const getQueryParam =
    (req: NextApiRequest) =>
    (prop: string): O.Option<string> =>
        extractQueryParam(req.query, prop);

/**
 * Send a 200 success response as JSON.
 * @param res
 * @returns we only have a return value to make it easier to compose in pipes. This function sends the requests without delay.
 */
export const sendSuccessResponse =
    (res: NextApiResponse) =>
    <T>(t: T): TA.Task<never> => {
        res.status(200).json(t);
        return TA.never; // make type checker happy
    };

/**
 * Send a @status error back to the client with @e as the message, plain text.
 * @param res
 * @returns we only have a return value to make it easier to compose in pipes. This function sends the requests without delay.
 */
export const sendErrorResponse =
    (res: NextApiResponse) =>
    (e: Err): TA.Task<never> => {
        logger.error(e);
        res.status(e.status).end(e.msg);
        return TA.never; // make type checker happy
    };

/**
 * Type used for representing Repsonse failures back to the client.
 */
export type Err = {
    status: number;
    msg: string;
    e?: Error;
    stack?: string;
};

/**
 * Converts an @Error to an @Err type.
 * @param e
 */
export const toErr = (e: Error): Err => ({
    status: 500,
    msg: e.message,
    e: e,
    stack: e.stack,
});
