// Various and sundry utils for dealign with data that comes back from the database.
// Ideally we would figure out a way to deal with all the null nonsense that can happen with optional
// fields in Prisma but for now it is this...

import { Prisma } from '@prisma/client';

export function mightBeNull<T extends string | string[] | number>(x: T | null | undefined): T {
    if (x == null || x == undefined) {
        return '' as T;
    }
    return x;
}

export type ConnectTypes =
    | Prisma.abundanceCreateOneWithoutSpeciesInput
    | Prisma.abundanceUpdateOneWithoutSpeciesInput
    | Prisma.alignmentCreateOneWithoutGallInput
    | Prisma.alignmentUpdateOneWithoutGallInput
    | Prisma.cellsCreateOneWithoutGallInput
    | Prisma.colorCreateOneWithoutGallInput
    | Prisma.shapeCreateOneWithoutGallInput
    | Prisma.wallsCreateOneWithoutGallInput
    | Prisma.familyCreateOneWithoutSpeciesInput
    | Prisma.familyUpdateWithoutSpeciesInput
    | Prisma.taxontypeCreateOneWithoutSpeciesInput
    | Prisma.taxontypeUpdateOneWithoutSpeciesInput
    | Prisma.hostCreateManyWithoutGallspeciesInput
    | Prisma.galllocationCreateWithoutGallInput
    | Prisma.galltextureCreateWithoutGallInput;

export function connectIfNotNull<T extends ConnectTypes>(fieldName: string, value: string | undefined): T {
    if (value) {
        return ({ connect: { [fieldName]: value } } as unknown) as T;
    } else {
        return ({} as unknown) as T;
    }
}

export type InsertFieldName = 'id' | 'location' | 'texture';

export function connectWithIds<T extends ConnectTypes>(fieldName: InsertFieldName, ids: readonly number[]): T[] {
    const key = fieldName as keyof T;
    return ids.map((l) => {
        // ugly casting due to what seems to be a TS bug. See: https://github.com/Microsoft/TypeScript/issues/13948
        return ({ [key]: { connect: { id: l } } } as unknown) as T;
    });
}
