/**
 * A base type that has an id of type number.
 */
export type WithID = { id: number };

/**
 * A type that uses conditional typing to extract the type that is inside of a Promise. Helpful when dealing
 * with database types (from Prisma).
 */
export type ExtractTFromPromise<T> = T extends Promise<infer S> ? S : never;

export type ExtractTFromPromiseReturn<T extends (args: any) => any> = ExtractTFromPromise<ReturnType<T>>;

export type Diff<T, U> = T extends U ? never : T;
export type Filter<T, U> = T extends U ? T : never;

/**
 * A generic type guard that takes in some unknown type that might be a T and a property that is part of T and returns
 * true if maybeT is of type T and false otherwise. Also includes a type predicate so that the compiler will recognize
 * this as a legit type guard.
 * @param maybeT an object that might be a T
 * @param aTProp a definite property of T
 */
export const isOfType = <T>(maybeT: unknown, aTProp: keyof T): maybeT is T => (maybeT as T)[aTProp] !== undefined;
