import { hasProp } from '../libs/utils/util';

function makeSetValueForLookup<F, D extends WithID, V>(setValue: (f: F, v: V[]) => void) {
    return (field: F, ids: (number | null | undefined)[] | undefined, lookup: D[], valField: string) => {
        if (!ids || ids.length < 1 || !ids[0]) return;

        const vals = ids.map((id) => {
            const val = lookup.find((v) => v.id === id);
            if (val && hasProp(val, valField)) {
                return val[valField] as V;
            } else {
                throw new Error(`Failed to lookup for ${field}.`);
            }
        });
        if (vals && vals.length > 0 && vals[0]) {
            setValue(field, vals);
        }
    };
}
export type WithID = { id: number };
export type LookupHook<T, S> = {
    setValueForLookup: (field: T, ids: (number | null | undefined)[] | undefined, lookup: S[], valField: string) => void;
};

/**
 * Hook to make setting values from lookups easier. This seems like the wrong way about this in that it would seem  to make
 * more sense to have the UI handle ids paired with the display value (string).
 * @param setValue  the function to change the form value
 * @typeParam F the type of the field name. This is a type to keep from receiving arbitrary strings.
 * @typeParam D the data type habors the id and the value that we will extract for display
 * @typeParam V the type of the value that will be extracted and set
 * @returns a function that can be used to set values extracted from a passed in lookup given an ID
 */
export function useWithLookup<F, D extends WithID, V>(setValue: (f: F, v: V[]) => void): LookupHook<F, D> {
    return {
        setValueForLookup: makeSetValueForLookup<F, D, V>(setValue),
    };
}
