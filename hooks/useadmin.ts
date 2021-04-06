import { yupResolver } from '@hookform/resolvers/yup';
import router from 'next/router';
import { useCallback, useEffect, useState } from 'react';
import { DeepPartial, FieldName, UnpackNestedValue, useForm, UseFormMethods } from 'react-hook-form';
import toast from 'react-hot-toast';
import * as yup from 'yup';
import { RenameEvent } from '../components/editname';
import { DeleteResult } from '../libs/api/apitypes';
import { WithID } from '../libs/utils/types';
import { AdminFormFields, useAPIs } from './useAPIs';

type AdminData<T, FormFields> = {
    data: T[];
    selected?: T;
    setSelected: (t: T | undefined) => void;
    showRenameModal: boolean;
    setShowRenameModal: (show: boolean) => void;
    error: string;
    setError: (err: string) => void;
    deleteResults?: DeleteResult;
    setDeleteResults: (dr: DeleteResult) => void;
    renameCallback: (doRename: (s: FormFields, e: RenameEvent) => void) => (e: RenameEvent) => void;
    form: UseFormMethods<FormFields>;
    formSubmit: (fields: FormFields) => Promise<void>;
    postUpdate: (res: Response) => void;
    postDelete: (id: number | string, result: DeleteResult) => void;
};

/**
 *  * A hook to handle universal adminstration data and logic. Works in conjunction with @Admin

 * @param type a string representing the type of data being Adminstered.
 * @param id the initial id that is selected, could be undefined
 * @param ts an array of the data type
 * @param update a function to create a new T from a give T and a new value for its "key"
 * @param toUpsertFields a function that converts FormFields to UpsertFields
 * @param apiConfig the configuration for the API endpoints
 * @param schema the form validation schema
 * @param updatedFormFields called when the data selection changes, should return an updated set of FormFields
 * @returns 
 */
const useAdmin = <T extends WithID, FormFields extends AdminFormFields<T>, UpsertFields>(
    type: string,
    id: string | undefined,
    ts: T[],
    update: (t: T, tName: string) => T,
    toUpsertFields: (fields: FormFields, keyField: string, id: number) => UpsertFields,
    apiConfig: { keyProp: keyof T; delEndpoint: string; upsertEndpoint: string },
    schema: yup.ObjectSchema,
    updatedFormFields: (t: T | undefined) => Promise<FormFields>,
): AdminData<T, FormFields> => {
    const [data, setData] = useState(ts);
    const [selected, setSelected] = useState<T | undefined>(id ? data.find((d) => d.id === parseInt(id)) : undefined);
    const [showModal, setShowModal] = useState(false);
    const [error, setError] = useState('');
    const [deleteResults, setDeleteResults] = useState<DeleteResult>();

    const { doDeleteOrUpsert } = useAPIs<T, UpsertFields>(apiConfig.keyProp, apiConfig.delEndpoint, apiConfig.upsertEndpoint);

    const form = useForm<FormFields>({
        mode: 'onBlur',
        resolver: yupResolver(schema),
    });

    const postDelete = (id: number | string, result: DeleteResult) => {
        setData(data.filter((d) => d.id !== id));
        setDeleteResults(result);
        setSelected(undefined);
        setError('');
        toast.success(`${type} deleted`);
        router.replace(``, undefined, { shallow: true });
    };

    const postUpdate = async (res: Response) => {
        const s = (await res.json()) as T;
        setSelected(s);
        let updated = data;
        if (data.find((d) => d.id === s.id) == undefined) {
            // add new if necessary
            updated.push(s);
        } else {
            // update data in place since name might have changed
            updated = data.filter((d) => d.id !== s.id);
            updated.push(s);
        }
        setError('');
        setData(updated);
        toast.success(`${type} Updated`);
        router.replace(`?id=${s.id}`, undefined, { shallow: true });
    };

    const formSubmit = async (fields: FormFields) => {
        await doDeleteOrUpsert(fields, postDelete, postUpdate, toUpsertFields)
            .then(() => {
                form.reset();
            })
            .catch((e: unknown) => setError(`Failed to save changes. ${e}.`));
    };

    const renameCallback = (doRename: (s: FormFields, e: RenameEvent) => void) => async (e: RenameEvent) => {
        if (selected == undefined) {
            const msg = `You encountered a bug. The current selection is invalid in the middle of a rename operation.`;
            console.error(msg);
            setError(msg);
            return;
        }
        const updated = update(selected, e.new);
        doRename(await updatedFormFields(updated), e);
    };

    const onDataChange = useCallback(async (t: T | undefined) => {
        const ff = await updatedFormFields(t);
        form.reset(ff as UnpackNestedValue<DeepPartial<FormFields>>);
        // must do this since the value is bound to a control that is controlled (i.e., no ref prop) so it will not get updated
        // during the reset. see: https://react-hook-form.com/api#reset
        form.setValue('value' as FieldName<FormFields>, [t as never]);
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, []);

    useEffect(() => {
        onDataChange(selected);
    }, [selected, onDataChange]);

    return {
        data: data,
        selected: selected,
        setSelected: setSelected,
        showRenameModal: showModal,
        setShowRenameModal: setShowModal,
        error: error,
        setError: setError,
        deleteResults: deleteResults,
        setDeleteResults: setDeleteResults,
        renameCallback: renameCallback,
        form: form,
        formSubmit: formSubmit,
        postUpdate: postUpdate,
        postDelete: postDelete,
    };
};

export default useAdmin;
