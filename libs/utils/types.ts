/**
 * A base type that has an id of type number.
 */
export type WithID = { id: number };

/**
 * A type that uses conditional typing to extract the type that is inside of a Promise. Helpful when dealing
 * with database types (from Prisma).
 */
export type ExtractTFromPromise<T> = T extends Promise<infer S> ? S : never;

export type Diff<T, U> = T extends U ? never : T;
export type Filter<T, U> = T extends U ? T : never;
