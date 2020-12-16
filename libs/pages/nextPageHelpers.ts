import { pipe } from 'fp-ts/lib/function';
import * as T from 'fp-ts/lib/Task';
import * as TE from 'fp-ts/lib/TaskEither';
import * as O from 'fp-ts/lib/Option';
import { TaskEither } from 'fp-ts/lib/TaskEither';
import { GetStaticPathsResult, GetStaticPropsContext } from 'next';
import { ParsedUrlQuery } from 'querystring';
import { errorThrow } from '../utils/util';

/**
 * Helper to hadnle the boilerplate for fetching static props for a next.js page.
 * @param f how to fetch the values
 * @param dataType a string describing the data type. Used in error messages.
 */
export async function getStaticPropsWith<T>(f: () => TaskEither<Error, readonly T[]>, dataType: string): Promise<readonly T[]> {
    return await pipe(
        f(),
        TE.getOrElse((e) => {
            console.error(`Got an error trying to fetch props for ${dataType}.`);
            throw e;
        }),
    )();
}

/**
 * Helper to handle the boilerplate of fetching data for static next js page generation.
 * @param id the id to pass to fId
 * @param fId how to fetch the data for static props.
 * @param dataType a string describing the data type. Used in error messages.
 * @param resultsRequired true if at least one result is required
 * @param many true if more than one result is expected
 */
export async function getStaticPropsWithId<T>(
    id: number,
    fId: (id: number) => TaskEither<Error, T[]>,
    dataType: string,
    resultsRequired = false,
    many = false,
): Promise<T[]> {
    // Do all of the error handling here so that the rendering side does not have to deal with it.
    // Plus this will all get called at build time and will uncover issues then rather than after deployment.
    const g = await pipe(
        fId(id),
        TE.getOrElse((e) => {
            console.error(`Failed to fetch ${dataType} from backend with ${dataType} id = '${id}'`);
            throw e;
        }),
    )();

    if (resultsRequired && g.length < 1) {
        const msg = `Failed to fetch ${dataType} from backend with ${dataType} id = '${id}'.`;
        console.error(msg);
        throw new Error(msg);
    } else if (!many && g.length > 1) {
        const msg = `Somehow we got more than one ${dataType} for ${dataType} id '${id}'.`;
        console.error(msg);
        throw new Error(msg);
    }

    return g;
}

/**
 * Helper that deals with all the rigormole of get a single item from the backend in getStaticProps()
 * @param context the next context from which to extrac the id to pass to fId
 * @param fId how to fetch the data for static props.
 * @param dataType a string describing the data type. Used in error messages.
 * @param resultsRequired true if at least one result is required
 * @param many true if more than one result is expected
 */
export async function getStaticPropsWithContext<T>(
    context: GetStaticPropsContext<ParsedUrlQuery>,
    fId: (id: number) => TaskEither<Error, T[]>,
    dataType: string,
    resultsRequired = false,
    many = false,
): Promise<T[]> {
    if (context === undefined || context.params === undefined || context.params.id === undefined) {
        throw new Error('An id must be passed!');
    } else if (Array.isArray(context.params.id)) {
        throw new Error(`Expected single id but got an array of ids ${context.params.id}.`);
    }

    return getStaticPropsWithId(parseInt(context.params.id), fId, dataType, resultsRequired, many);
}

/**
 * Helper to handle boilerplate for fetching IDs for static path generation.
 * @param fIds how to fetch the ids.
 */
export async function getStaticPathsFromIds(fIds: () => TaskEither<Error, string[]>): Promise<GetStaticPathsResult> {
    const toPath = (ids: string[]) =>
        ids.map((id) => ({
            params: { id: id },
        }));

    const ids = fIds();

    const paths = await pipe(
        ids,
        TE.getOrElse((e) => {
            errorThrow(e);
            return T.of(new Array<string>());
        }),
        T.map(toPath),
    )();

    return { paths, fallback: false };
}
