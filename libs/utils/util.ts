// Welcome to the inevitable utils file!!!

import { constant, pipe } from 'fp-ts/lib/function';
import * as T from 'fp-ts/lib/Task';
import * as TE from 'fp-ts/lib/TaskEither';
import * as O from 'fp-ts/lib/Option';
import { logger } from './logger';

/**
 * Checks an object, o, for the presence of the prop.
 * @param o the object to check
 * @param prop the prop to check for
 */
export function hasProp<T extends unknown, K extends PropertyKey>(o: T, prop: K): o is T & Record<K, unknown> {
    if (!o) return false;

    return Object.prototype.hasOwnProperty.call(o, prop);
}

export function bugguideUrl(species: string): string {
    return `https://bugguide.net/index.php?q=search&keys=${encodeURI(species)}&search=Search`;
}

export function iNatUrl(species: string): string {
    return `https://www.inaturalist.org/search?q=${encodeURI(species)}`;
}

export function gScholarUrl(species: string): string {
    return `https://scholar.google.com/scholar?hl=en&q=${species}`;
}

/**
 * Returns a random integer between [min, max]
 * @param min
 * @param max
 */
export function randInt(min: number, max: number): number {
    if (min >= max) throw new Error(`The min value must be smaller than the max value. ${min} >= ${max}!`);
    return Math.floor(Math.random() * (max - min + 1) + min);
}

/**
 * This is used to bridge the FP world TaskEithers into Promises while consistently handling failures.
 * @param s
 */
export const mightFail = <T>(defaultT: () => T) => async <S extends TE.TaskEither<Error, T>>(s: S): Promise<T> => {
    return pipe(
        s,
        TE.getOrElse((e) => {
            logger.error(e);
            return T.of(defaultT());
        }),
    )();
};

export const mightFailWithArray = <T>(): (<S extends TE.TaskEither<Error, Array<T>>>(s: S) => Promise<Array<T>>) =>
    mightFail(constant(new Array<T>()));

export const mightFailWithStringArray = mightFailWithArray<string>();

export const mightFailWithMap = <K, V>(): (<S extends TE.TaskEither<Error, Map<K, V>>>(s: S) => Promise<Map<K, V>>) =>
    mightFail(constant(new Map<K, V>()));
/**
 * Cute litte hacky function to handle an error. It always throws. Being a function with a generic return type it allows
 * us to throw from within a pipe (not what one would normally want but if you want to stop the error propagation this
 * is how you do it).
 * @param e an error
 */
export const errorThrow = <T>(e: Error): T => {
    logger.error(e);
    throw e;
};

/**
 * A helper to correctly convert some thrown value into an Error object (so we get stack traces).
 * @param e some thing that was thrown and caught
 */
export function handleError(e: unknown): Error {
    if (e instanceof Error) {
        return e;
    } else {
        // since in TS/JS you can throw anything, including caution to the wind... :) or really :(
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        return new Error(e as any);
    }
}

/**
 * If the given text is longer than the passed in len then truncate the text and add ... and return.
 * @param words the number of words at which to truncate and add ...
 */
export const truncateAtWord = (words: number) => (s: string): string => {
    if (s.length > words) {
        return s.split(' ').splice(0, 40).join(' ') + '...';
    } else {
        return s;
    }
};

export const capitalizeFirstLetter = (s: string): string => s.charAt(0).toUpperCase() + s.slice(1);

/**
 *
 * @param t
 * @param adapt
 */
export const optionalWith = <T, S>(t: T | null, adapt: (t: T) => S): O.Option<S> => {
    if (t == null) return O.none;
    return O.of(adapt(t));
};
