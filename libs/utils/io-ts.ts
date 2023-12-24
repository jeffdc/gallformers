// stuff for making io-ts nicer
import * as E from 'fp-ts/lib/Either';
import { pipe } from 'fp-ts/lib/function';
import * as t from 'io-ts';

// From: https://github.com/gcanti/io-ts/issues/216#issuecomment-599020040
/**
 * this utility function can be used to turn a TypeScript enum into an io-ts codec.
 */
export function fromEnum<EnumType extends string>(
    enumName: string,
    theEnum: Record<string, EnumType>,
): t.Type<EnumType, EnumType, unknown> {
    const isEnumValue = (input: unknown): input is EnumType => Object.values<unknown>(theEnum).includes(input);

    return new t.Type<EnumType>(
        enumName,
        isEnumValue,
        (input, context) => (isEnumValue(input) ? t.success(input) : t.failure(input, context)),
        t.identity,
    );
}

/**
 *
 * @param e an Either
 * @param defaultValue the default value to return if isLeft(e) === true
 * @returns if isRight(e) then the value in e, otherwise defaultValue with a console.error logged
 */
export function decodeWithDefault<E, T>(e: E.Either<E, T>, defaultValue: T): T {
    return pipe(
        e,
        E.match((err) => {
            console.error(`Failed to decode value from Either "${e}". Got error below`);
            console.dir(err);
            return defaultValue;
        }, t.identity),
    );
}
