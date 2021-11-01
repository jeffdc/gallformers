import { yupResolver } from '@hookform/resolvers/yup';
import router from 'next/router';
import React, { useCallback, useEffect, useState } from 'react';
import { Button, Col, Row } from 'react-bootstrap';
import { DeepPartial, Path, UnpackNestedValue, useForm, UseFormReturn } from 'react-hook-form';
import toast from 'react-hot-toast';
import * as yup from 'yup';
import { AnyObject, AssertsShape, ObjectShape, TypeOfShape } from 'yup/lib/object';
import { Maybe } from 'yup/lib/types';
import { ConfirmationOptions } from '../components/confirmationdialog';
import { RenameEvent } from '../components/editname';
import Typeahead, { TypeaheadLabelKey } from '../components/Typeahead';
import { DeleteResult } from '../libs/api/apitypes';
import { WithID } from '../libs/utils/types';
import { hasProp } from '../libs/utils/util';
import { AdminFormFields, useAPIs } from './useAPIs';
import { useConfirmation } from './useconfirmation';

type AdminData<T, FormFields> = {
    setData: (ts: T[]) => void;
    selected?: T;
    setSelected: (t: T | undefined) => void;
    showRenameModal: boolean;
    setShowRenameModal: (show: boolean) => void;
    isValid: boolean;
    error: string;
    setError: (err: string) => void;
    deleteResults?: DeleteResult;
    setDeleteResults: (dr: DeleteResult) => void;
    renameCallback: (e: RenameEvent) => void;
    form: UseFormReturn<FormFields>;
    confirm: (options: ConfirmationOptions) => Promise<void>;
    formSubmit: (fields: FormFields) => Promise<void>;
    postUpdate: (res: Response) => void;
    postDelete: (id: number | string, result: DeleteResult) => void;
    mainField: (key: TypeaheadLabelKey<T>, placeholder: string) => JSX.Element;
    deleteButton: (warning: string, customDeleteHandler?: (fields: FormFields) => Promise<void>) => JSX.Element;
};

/**
 *  * A hook to handle universal adminstration data and logic. Works in conjunction with @Admin

 * @param type a string representing the type of data being Adminstered.
 * @param id the initial id that is selected, could be undefined
 * @param ts an array of the data type
 * @param rename a function to create a new T from a given T and a new value for its "name" aka the key
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
    rename: (t: T, e: RenameEvent, confirm: (options: ConfirmationOptions) => Promise<void>) => Promise<T>,
    toUpsertFields: (fields: FormFields, keyField: string, id: number) => UpsertFields,
    apiConfig: { keyProp: keyof T; delEndpoint: string; upsertEndpoint: string; delQueryString?: () => string },
    schema: yup.ObjectSchema<ObjectShape, AnyObject, Maybe<TypeOfShape<ObjectShape>>, Maybe<AssertsShape<ObjectShape>>>,
    updatedFormFields: (t: T | undefined) => Promise<FormFields>,
    reloadOnUpdate = false,
    createNew?: (v: string) => T,
): AdminData<T, FormFields> => {
    const [data, setData] = useState(ts);
    const [selected, setSelected] = useState<T | undefined>(id ? data.find((d) => d.id === parseInt(id)) : undefined);
    const [showModal, setShowModal] = useState(false);
    const [error, setError] = useState('');
    const [deleteResults, setDeleteResults] = useState<DeleteResult>();

    const { doDeleteOrUpsert } = useAPIs<T, UpsertFields>(
        apiConfig.keyProp,
        apiConfig.delEndpoint,
        apiConfig.upsertEndpoint,
        apiConfig.delQueryString,
    );

    const form = useForm<FormFields>({
        mode: 'onBlur',
        resolver: yupResolver(schema),
    });

    const { isValid } = form.formState;

    const confirm = useConfirmation();

    const theMainField = (labelKey: TypeaheadLabelKey<T>, placeholder: string) => {
        return (
            <>
                <Typeahead
                    name={'mainField' as Path<FormFields>}
                    control={form.control}
                    options={data}
                    labelKey={labelKey}
                    selected={selected ? [selected] : []}
                    placeholder={placeholder}
                    clearButton
                    isInvalid={!!form.formState.errors.mainField}
                    newSelectionPrefix={`Add a new ${placeholder}: `}
                    allowNew={!!createNew}
                    onChange={(s) => {
                        if (s.length <= 0) {
                            setSelected(undefined);
                            router.replace(``, undefined, { shallow: true });
                        } else {
                            if (hasProp(s[0], 'customOption') && hasProp(s[0], 'name')) {
                                if (createNew) {
                                    const x = createNew(s[0].name as string);
                                    setSelected(x);
                                }
                                router.replace(``, undefined, { shallow: true });
                            } else {
                                setSelected(s[0]);
                                router.replace(`?id=${s[0].id}`, undefined, { shallow: true });
                            }
                        }
                    }}
                />
                {form.formState.errors.mainField && <span className="text-danger">{`The ${placeholder} is required.`}</span>}
            </>
        );
    };

    const doDelete = async (deleteHandler?: (fields: FormFields) => Promise<void>) => {
        return confirm({
            variant: 'danger',
            catchOnCancel: true,
            title: 'Are you sure want to delete?',
            message: `This will delete the current ${type} and all associated data. Do you want to continue?`,
        })
            .then(() => {
                if (deleteHandler) {
                    deleteHandler({ ...form.getValues(), del: true } as FormFields);
                } else {
                    formSubmit({ ...form.getValues(), del: true } as FormFields);
                }
            })
            .catch(() => Promise.resolve());
    };

    const deleteButton = (warning: string, customDeleteHandler?: (fields: FormFields) => Promise<void>) => {
        return (
            <Row hidden={!selected}>
                <Col>
                    <Row>
                        <Col className="">
                            <Button variant="danger" className="" onClick={() => doDelete(customDeleteHandler)}>
                                Delete
                            </Button>
                        </Col>
                    </Row>
                    <Row>
                        <Col>
                            <em className="text-danger">{warning}</em>
                        </Col>
                    </Row>
                </Col>
            </Row>
        );
    };

    const postDelete = (id: number | string, result: DeleteResult) => {
        setData(data.filter((d) => d.id !== id));
        setSelected(undefined);
        router.replace(``, undefined, { shallow: true });
        setDeleteResults(result);
        setError('');
        toast.success(`${type} deleted`);
    };

    const postUpdate = async (res: Response) => {
        const s = (await res.json()) as T;
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
        setSelected(s);
        toast.success(`${type} Updated`);
        router.replace(`?id=${s.id}`, undefined, { shallow: !reloadOnUpdate });
    };

    const formSubmit = async (fields: FormFields) => {
        await doDeleteOrUpsert(fields, postDelete, postUpdate, toUpsertFields)
            .then(() => {
                form.reset();
            })
            .catch((e: unknown) => setError(`Failed to save changes. ${e}.`));
    };

    const renameCallback = async (e: RenameEvent) => {
        if (selected == undefined) {
            const msg = `You encountered a bug. The current selection is invalid in the middle of a rename operation.`;
            console.error(msg);
            setError(msg);
            return;
        }
        const updated = await rename(selected, e, confirm);
        formSubmit(await updatedFormFields(updated));
    };

    const onDataChange = useCallback(async (t: T | undefined) => {
        const ff = await updatedFormFields(t);
        form.reset(ff as UnpackNestedValue<DeepPartial<FormFields>>);
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, []);

    useEffect(() => {
        onDataChange(selected);
    }, [selected, onDataChange]);

    return {
        setData: setData,
        selected: selected,
        setSelected: setSelected,
        showRenameModal: showModal,
        setShowRenameModal: setShowModal,
        isValid: isValid,
        error: error,
        setError: setError,
        deleteResults: deleteResults,
        setDeleteResults: setDeleteResults,
        renameCallback: renameCallback,
        form: form,
        confirm: confirm,
        formSubmit: formSubmit,
        postUpdate: postUpdate,
        postDelete: postDelete,
        mainField: theMainField,
        deleteButton: deleteButton,
    };
};

export default useAdmin;
