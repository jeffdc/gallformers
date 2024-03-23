// Welcome to the inevitable utils file!!!

import { constant, constFalse, constTrue, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import * as T from 'fp-ts/lib/Task.js';
import * as TE from 'fp-ts/lib/TaskEither';
import { logger } from './logger.ts';

/**
 * Checks an object, o, for the presence of the prop.
 * @param o the object to check
 * @param prop the prop to check for
 */
export function hasProp<T, K extends PropertyKey>(o: T, prop: K): o is T & Record<K, unknown> {
    if (!o) return false;

    return Object.prototype.hasOwnProperty.call(o, prop);
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
export const mightFail =
    <T>(defaultT: () => T) =>
    async <S extends TE.TaskEither<Error, T>>(s: S): Promise<T> => {
        return pipe(
            s,
            TE.getOrElse((e) => {
                logger.error(e);
                return T.of(defaultT());
            }),
        )();
    };

export const mightFailWithOptional = <T>(): (<S extends TE.TaskEither<Error, O.Option<T>>>(s: S) => Promise<O.Option<T>>) =>
    mightFail(constant(O.none as O.Option<T>));

export const mightFailWithArray = <T>(): (<S extends TE.TaskEither<Error, Array<T>>>(s: S) => Promise<Array<T>>) =>
    mightFail(constant(new Array<T>()));

export const mightFailWithStringArray = mightFailWithArray<string>();

export const mightFailWithMap = <K, V>(): (<S extends TE.TaskEither<Error, Map<K, V>>>(s: S) => Promise<Map<K, V>>) =>
    mightFail(constant(new Map<K, V>()));
/**
 * Cute little hacky function to handle an error. It always throws. Being a function with a generic return type it allows
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
export const truncateAtWord =
    (words: number) =>
    (s: string): string => {
        if (s.length > words) {
            return s.split(' ').splice(0, 40).join(' ') + '...';
        } else {
            return s;
        }
    };

const doToFirstLetter = (s: string | undefined, capitalize: boolean): string => {
    if (s == undefined || s.length < 1) return '';

    return capitalize ? s.charAt(0).toUpperCase() + s.slice(1) : s.charAt(0).toLowerCase() + s.slice(1);
};

export const capitalizeFirstLetter = (s: string): string => doToFirstLetter(s, true);

export const lowercaseFirstLetter = (s: string): string => doToFirstLetter(s, false);

export const pluralize = (s: string): string => {
    if (s.endsWith('y')) {
        return `${s.slice(0, s.length - 1)}ies`;
    } else if (s.endsWith('s')) {
        return s;
    } else {
        return `${s}s`;
    }
};

/**
 *
 * @param t
 * @param adapt
 */
export const optionalWith = <T, S>(t: T | null, adapt: (t: T) => S): O.Option<S> => {
    if (t == null) return O.none;
    return O.of(adapt(t));
};

export const check = <A, B>(a: O.Option<A>, b: O.Option<B>, f: (a: A, b: B) => boolean): boolean =>
    pipe(
        a,
        // if a is None, then that is OK for the search, just means "any" match for that property.
        O.fold(constTrue, (a) =>
            pipe(
                b,
                // however, if b is None, then there is no value and it can not match a (a can not be None at this point).
                O.fold(constFalse, (b) => f(a, b)),
            ),
        ),
    );

export const serializeOption = <T>(o: O.Option<T>): string =>
    JSON.stringify(O.isNone(o) ? { type: 'None' } : { type: 'Some', value: o.value });

export const deserializeOption = <T>(s: string): O.Option<T> => {
    const o = JSON.parse(s);
    return o.type === 'None' ? O.none : O.some(o.value);
};

/**
 * Takes a simple CSV of numbers (just commas with no escaping) and returns it as number[].
 * @param s
 */
export const csvAsNumberArr = (s: string): number[] => {
    const arr = s
        .split(',')
        .map((v) => v.trim())
        .map((n) => parseInt(n));

    // check for NaNs
    if (arr.filter((n) => n !== n).length > 0) return [];

    return arr;
};

/**
 *
 * @param n
 */
export const extractGenus = (n: string): string => {
    return n.split(' ')[0];
};

export const sessionUserOrUnknown = (user: string | null | undefined): string => (user ? user : 'UNKNOWN!');

/**
 * These are all valid names:
 * Foo bar
 * Foo bar-baz
 * Foo bar-baz-boo
 * Foo bar-baz (boo)
 * Foo bar-baz (boo) (boo)
 * Foo x bar
 * Foo x bar-baz
 * Foo x bar-baz (boo)
 * Foo x bar-baz (boo) (boo)
 *
 * These are not:
 * Foo s bar
 * Foo bar agamic
 * foo bar
 * F bar
 *  Foo bar <-- note leading space on this one
 *
 */
export const SPECIES_NAME_REGEX = /(^[A-Z][a-z]+ (x|X)?\s?[a-z-]+\s?(\(.+\)\s*)*$)/;

const speciesRegEx = new RegExp(SPECIES_NAME_REGEX);

/**
 *
 * @param s Convenience function to test for a valid species name.
 * @returns
 */
export const isValidSpeciesName = (s: string): boolean => speciesRegEx.test(s);
