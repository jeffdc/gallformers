// Various and sundry utils for dealign with data that comes back from the database.
// Ideally we would figure out a way to deal with all the null nonsense that can happen with optional
// fields in Prisma but for now it is this...

import { Prisma } from '@prisma/client';

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
    | Prisma.hostCreateWithoutGallspeciesInput
    | Prisma.galllocationCreateWithoutGallInput
    | Prisma.galltextureCreateWithoutGallInput
    | Prisma.sourceCreateWithoutImageInput
    | Prisma.sourceCreateOneWithoutImageInput;

export function connectIfNotNull<T extends ConnectTypes, V>(fieldName: string, value: V | undefined): T {
    if (value) {
        return ({ connect: { [fieldName]: value } } as unknown) as T;
    } else {
        return ({} as unknown) as T;
    }
}

export type InsertFieldName = 'id' | 'location' | 'texture' | 'hostspecies';

export function connectWithIds<T extends ConnectTypes>(fieldName: InsertFieldName, ids: readonly number[]): T[] {
    const key = fieldName as keyof T;
    return ids.map((l) => {
        // ugly casting due to what seems to be a TS bug. See: https://github.com/Microsoft/TypeScript/issues/13948
        return ({ [key]: { connect: { id: l } } } as unknown) as T;
    });
}

export function createWithIds<T extends ConnectTypes>(fieldName: InsertFieldName, ids: readonly number[]): T[] {
    const key = fieldName as keyof T;
    return ids.map((l) => {
        // ugly casting due to what seems to be a TS bug. See: https://github.com/Microsoft/TypeScript/issues/13948
        return ({ [key]: { create: { id: l } } } as unknown) as T;
    });
}

export function mapToIdsForPrisma<T extends ConnectTypes>(ids: number[]): T[] {
    return ids.map((id) => {
        return ({
            id: id,
        } as unknown) as T;
    });
}

export const extractId = <T extends { id: number }>(o: T): number => o.id;
