// stuff for making io-ts nicer
import * as E from 'fp-ts/lib/Either';
import { identity, pipe } from 'fp-ts/lib/function';
import t, { Type } from 'io-ts';

// From: https://github.com/gcanti/io-ts/issues/216#issuecomment-599020040
/**
 * this utility function can be used to turn a TypeScript enum into a io-ts codec.
 */
export function fromEnum<EnumType>(enumName: string, theEnum: Record<string, string | number>) {
    const isEnumValue = (input: unknown): input is EnumType => Object.values<unknown>(theEnum).includes(input);

    return new Type<EnumType>(
        enumName,
        isEnumValue,
        (input, context) => (isEnumValue(input) ? t.success(input) : t.failure(input, context)),
        identity,
    );
}

/**
 *  Takes the result of a decode (an Either) and unpacks the value. If there is any error it will get logged to
 *  the Console and will then return and empty object cast to the T typw. I know, janky.
 * */
export function unsafeDecode<T, E>(e: E.Either<E, T>): T {
    return pipe(
        e,
        E.match((err) => {
            console.error(err);
            return {} as T;
        }, identity),
    );
}
