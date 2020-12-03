import { pipe } from 'fp-ts/lib/function';
import * as T from 'fp-ts/lib/Task';
import * as TE from 'fp-ts/lib/TaskEither';
import { TaskEither } from 'fp-ts/lib/TaskEither';
import { GetStaticPathsResult, GetStaticPropsContext } from 'next';
import { ParsedUrlQuery } from 'querystring';
import { errorThrow, mightFail } from '../utils/util';

/**
 * Helper that deals with all the rigormole of get a single item from the backend in getStaticProps()
 */
export async function getStaticPropsWithId<T>(
    context: GetStaticPropsContext<ParsedUrlQuery>,
    fId: (id: string) => TaskEither<Error, T[]>,
    propName: string,
): Promise<T[]> {
    if (context === undefined || context.params === undefined || context.params.id === undefined) {
        throw new Error('An id must be passed!');
    } else if (Array.isArray(context.params.id)) {
        throw new Error(`Expected single id but got an array of ids ${context.params.id}.`);
    }

    // Do all of the error handling here so that the rendering side does not have to deal with it.
    // Plus this will all get called at build time and will uncover issues then rather than after deployment.
    const g = (await mightFail(fId(context.params.id))) as T[];
    if (g.length < 1) {
        const msg = `Failed to fetch ${propName} from backend with ${propName} id = '${context.params.id}'.`;
        console.error(msg);
        throw new Error(msg);
    } else if (g.length > 1) {
        const msg = `Somehow we got more than ${propName} for ${propName} id '${context.params.id}'.`;
        console.error(msg);
        throw new Error(msg);
    }

    return g;
}

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
