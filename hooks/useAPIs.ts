import { DeleteResult } from '../libs/api/apitypes';
import { logger } from '../libs/utils/logger.ts';
import { WithID } from '../libs/utils/types';
import { hasProp } from '../libs/utils/util';

/**
 * The type returned by the hook.
 */
export type UseAPIsType<T, U> = {
    /** A function to delete or upsert Ts.
     * @param data the form data
     * @param postDelete a callback that will be invoked after a successful deletion, it will return a @DeleteResult
     * @param postUpdate a callback that will be invoked after a successful upsert.
     */
    doDeleteOrUpsert: <FF extends AdminFormFields<T>>(
        data: FF,
        postDelete: (id: string | number, result: DeleteResult) => void,
        postUpdate: (res: Response) => void,
        convertFieldsToUpsert: (fields: FF, keyFieldVal: string, id: number) => U,
    ) => Promise<void>;
};

/**
 * A hook to make implementing the admin forms easier. The hook handles all of the plumbing of doing a delete or an upsert
 * with minimal fuss from the caller of the hook. The prerequisites are:
 * 1) have a type defined that extends AdminFormFields (this must be same type passed to the useForm hook). This type
 * should exclude the id (if present in T).
 * 2) have a "key" field in the form that takes an object type (T). This is the field that is the key for insert vs update.
 * This field *must* be named 'mainField' when defining the form. Its types is bound when you satisfy prerequisite #1.
 *
 * @param keyProp the name of the property within T that is contains the actual value that is displayed to the user in the
 *  form. This name is also what gets bound by the Typeahead component to new items which in turn comes from the 'labelKey'
 *  that is passed to the typeahead.
 * @param delEndpoint the url path fragment to the delete API for @T
 * @param upsertEndpoint the url path fragment to the upsert API for @T
 * @returns a function that can be used to delete or upsert T data. @see UseAPIsType
 */
export const useAPIs = <T extends WithID, U>(
    keyProp: keyof T,
    delEndpoint: string,
    upsertEndpoint: string,
    delQueryString?: () => string,
): UseAPIsType<T, U> => {
    const doDeleteOrUpsert = async <FF extends AdminFormFields<T>>(
        data: FF,
        postDelete: (id: string | number, result: DeleteResult) => void,
        postUpdate: (res: Response) => void,
        convertFieldsToUpsert: (fields: FF, keyFieldVal: string, id: number) => U,
    ) => {
        try {
            const value = data.mainField[0];
            if (data.del && hasProp(value, 'id')) {
                const endpoint = delQueryString ? `${delEndpoint}${delQueryString()}` : `${delEndpoint}${value.id}`;
                const res = await fetch(endpoint, {
                    method: 'DELETE',
                });

                if (res.status === 200) {
                    const result: DeleteResult = await res.json();
                    postDelete(value.id, result);
                } else {
                    const txt = await res.text();
                    throw new Error(`code: ${res.status} err: ${txt}`);
                }
            } else {
                const keyFieldVal = value[keyProp] as unknown as string;
                const updated = convertFieldsToUpsert(data, keyFieldVal.trim(), value.id);

                const res = await fetch(upsertEndpoint, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify(updated),
                });

                if (res.status === 200) {
                    postUpdate(res);
                } else {
                    const txt = await res.text();
                    throw new Error(`code: ${res.status} err: ${txt}`);
                }
            }
        } catch (e) {
            const err = `Failed with endpoint "${data.del ? 'delete: ' + delEndpoint : 'upsert: ' + upsertEndpoint}". ${
                delQueryString ? 'delQueryString: ' + delEndpoint : ''
            } ${e}`;

            logger.error(err);
            throw new Error(
                `Failed to update/delete data. Check the console and open a new issue in Github copying any errors seen in the console as well as info about what you were doing when this occurred. \n${err}`,
            );
        }
    };

    return {
        doDeleteOrUpsert: doDeleteOrUpsert,
    };
};
