import { DevTool } from '@hookform/devtools';
import axios from 'axios';
import * as t from 'io-ts';
import { useSession } from 'next-auth/react';
import router from 'next/router';
import React, { useCallback, useEffect, useState } from 'react';
import { Button, Col, Row } from 'react-bootstrap';
import { AsyncTypeahead, Typeahead } from 'react-bootstrap-typeahead';
import { Option as TypeaheadOption } from 'react-bootstrap-typeahead/types/types';
import { DefaultValues, FieldErrors, FieldValues, Path, UseFormReturn, useForm } from 'react-hook-form';
import toast from 'react-hot-toast';
import { superAdmins } from '../components/auth';
import { ConfirmationOptions } from '../components/confirmationdialog';
import { RenameEvent } from '../components/editname';
import { DeleteResult } from '../libs/api/apitypes';
import { WithID } from '../libs/utils/types';
import { hasProp, pluralize } from '../libs/utils/util';
import { useAPIs } from './useAPIs';
import { useConfirmation } from './useConfirmation';

/** The schema has to be generated at runtime since the type is not known until then. */
export const adminFormFieldsSchema = <T,>(schemaT: t.Type<T>) =>
    t.type({
        mainField: t.array(schemaT),
        del: t.boolean,
    });

// Have to define this rather than use io-ts type magic since we do not know the types now.
export type AdminFormFields<T> = {
    mainField: T[];
    del: boolean;
};

type AdminData<T, FormFields extends FieldValues> = {
    data: T[];
    setData: (ts: T[]) => void;
    selected?: T;
    setSelected: (t: T | undefined) => void;
    showRenameModal: boolean;
    setShowRenameModal: (show: boolean) => void;
    isValid: boolean;
    isDirty: boolean;
    errors: FieldErrors<FormFields>;
    error: string;
    setError: (err: string) => void;
    deleteResults?: DeleteResult;
    setDeleteResults: (dr: DeleteResult) => void;
    renameCallback: (e: RenameEvent) => void;
    nameExists: (name: string) => Promise<boolean>;
    form: UseFormReturn<FormFields>;
    confirm: (options: ConfirmationOptions) => Promise<void>;
    formSubmit: (fields: FormFields) => Promise<void>;
    postUpdate: (res: Response) => void;
    postDelete: (id: number | string, result: DeleteResult) => void;
    mainField: (placeholder: string, asyncProps?: AsyncMainFieldProps) => JSX.Element;
    deleteButton: (
        warning: string,
        needSuperAdmin: boolean,
        customDeleteHandler?: (fields: FormFields) => Promise<void>,
    ) => JSX.Element;
    saveButton: () => JSX.Element;
    isSuperAdmin: boolean;
};

export type AsyncMainFieldProps = {
    /* Constructs the URL for the search endpoint provided the search query string. */
    searchEndpoint: (s: string) => string;

    /* Message displayed in the menu when there is no user input. */
    promptText?: React.ReactNode;

    /* Message to display in the menu while the request is pending. */
    searchText?: React.ReactNode;

    /* Whether or not the component should cache query results. */
    useCache?: boolean;

    /* The debounce delay in ms. */
    delay?: number;
};

/**
 *  * A hook to handle universal administration data and logic. Works in conjunction with @Admin

 * @param type a string representing the type of data being Administered.
 * @param mainFieldName the name of the field in the form data that maps to the mainField
 * @param id the initial id that is selected, could be undefined
 * @param rename a function to create a new T from a given T and a new value for its "name" aka the key
 * @param toUpsertFields a function that converts FormFields to UpsertFields
 * @param apiConfig the configuration for the API endpoints
 * @param schema the form validation schema
 * @param updatedFormFields called when the data selection changes, should return an updated set of FormFields
 * @param reloadOnUpdate should the form reload on an update - defaults to false
 * @param createNew an optional function for creating a new T from a string value
 * @param initialData an optional array of data to initially populate the form with
 * @returns AdminData<T, FormFields> the data needed to build and run an admin form
 */
const useAdmin = <T extends WithID, FormFields extends AdminFormFields<T>, UpsertFields>(
    type: string,
    mainFieldName: keyof T,
    id: string | undefined,
    rename: (t: T, e: RenameEvent, confirm: (options: ConfirmationOptions) => Promise<void>) => Promise<T>,
    toUpsertFields: (fields: FormFields, keyField: string, id: number) => UpsertFields,
    apiConfig: {
        delEndpoint: string;
        upsertEndpoint: string;
        delQueryString?: () => string;
        nameExistsEndpoint?: (name: string) => string;
    },
    updatedFormFields: (t: T | undefined) => Promise<FormFields>,
    reloadOnUpdate = false,
    createNew?: (v: string) => T,
    initialData?: T[],
): AdminData<T, FormFields> => {
    const session = useSession();
    const isSuperAdmin = !!(session?.data?.user?.name && superAdmins.includes(session.data.user.name));

    const [data, setData] = useState<T[]>(initialData ?? []);
    const [isLoading, setIsLoading] = useState(false);
    const [selected, setSelected] = useState<T | undefined>(
        id && initialData ? initialData.find((d) => d.id === parseInt(id)) : undefined,
    );
    const [showModal, setShowModal] = useState(false);
    const [error, setError] = useState('');
    const [deleteResults, setDeleteResults] = useState<DeleteResult>();

    const { doDeleteOrUpsert } = useAPIs<T, UpsertFields>(
        mainFieldName,
        apiConfig.delEndpoint,
        apiConfig.upsertEndpoint,
        apiConfig.delQueryString,
    );

    const { formState: formState, ...form } = useForm<FormFields>({
        mode: 'onChange',
        reValidateMode: 'onChange',
    });

    // subscribe to relevant form state - the form lib uses a proxy object to provide (IMO) a mandatory optimization that creates confusion
    const { isDirty, isValid, errors } = formState;

    const labelKey = mainFieldName as string;

    const confirm = useConfirmation();

    const onChange = (s: TypeaheadOption[]) => {
        console.log(`JDC: useAdmin:onChange -- ${JSON.stringify(s, null, '  ')}`);
        if (s.length <= 0) {
            setSelected(undefined);
            router.replace(``, undefined, { shallow: true });
        } else {
            // the Typeahead is weird and new items will have the property 'customOption'... 🤷‍♂️
            if (hasProp(s[0], 'customOption') && hasProp(s[0], mainFieldName)) {
                if (createNew) {
                    const x = createNew(s[0][mainFieldName] as string);
                    setSelected(x);
                }
                router.replace(``, undefined, { shallow: true });
            } else {
                const t = s[0] as T;
                setSelected(t);
                router.replace(`?id=${t.id}`, undefined, { shallow: true });
            }
        }
    };

    const handleSearch = (asyncProps: AsyncMainFieldProps) => (s: string) => {
        setIsLoading(true);

        axios
            .get<T[]>(asyncProps.searchEndpoint(s))
            .then((resp) => {
                setData(resp.data);
                setIsLoading(false);
            })
            .catch((e) => {
                console.error(e);
            });
    };

    const theMainField = (placeholder: string, asyncProps?: AsyncMainFieldProps) => {
        const { name, onChange: _oC, ...rest } = form.register('mainField' as Path<FormFields>);
        return (
            <>
                <DevTool control={form.control} placement="top-right" />
                <ul>
                    <li>
                        <code>{`IsValid: ${isValid} -- isDirty: ${isDirty}`}</code>
                    </li>
                    <li>
                        <code>{`Err: ${JSON.stringify(errors)}`}</code>
                    </li>
                    <li>
                        <code>{`Selected: ${JSON.stringify(selected)}`}</code>
                    </li>
                </ul>

                {asyncProps ? (
                    <AsyncTypeahead
                        id={name}
                        options={data}
                        labelKey={labelKey}
                        selected={selected ? [selected] : []}
                        placeholder={`Start typing a ${placeholder} name to begin`}
                        clearButton
                        isInvalid={!!errors.mainField}
                        newSelectionPrefix={`Add a new ${placeholder}: `}
                        allowNew={!!createNew}
                        onChange={onChange}
                        onSearch={handleSearch(asyncProps)}
                        minLength={1}
                        delay={500}
                        useCache={true}
                        isLoading={isLoading}
                        // needed when using async
                        filterBy={() => true}
                        promptText={`Type in a ${type} name.`}
                        searchText={`Searching for ${pluralize(type)}...`}
                        {...asyncProps}
                        {...rest}
                    />
                ) : (
                    <Typeahead
                        id={name}
                        options={data}
                        placeholder={placeholder}
                        labelKey={labelKey}
                        clearButton
                        isInvalid={!!errors.mainField}
                        newSelectionPrefix={`Add a new ${placeholder}: `}
                        allowNew={!!createNew}
                        onChange={onChange}
                        {...rest}
                    />
                )}
            </>
        );
    };

    const doDelete = async (deleteHandler?: (fields: FormFields) => Promise<void>) => {
        return confirm({
            variant: 'danger',
            catchOnCancel: true,
            title: 'Are you sure want to delete?',
            message: `This will delete the currently selected ${type} and all associated data. Do you want to continue?`,
        })
            .then(async () => {
                const vals = form.getValues();
                if (deleteHandler) {
                    await deleteHandler({ ...vals, del: true } as FormFields);
                } else {
                    await formSubmit({ ...vals, del: true } as FormFields);
                }
                // remove from the local store as well
                setData(data.filter((d) => d.id !== vals.mainField[0].id));
            })
            .catch(() => Promise.resolve());
    };

    const deleteButton = (
        warning: string,
        needSuperAdmin = false,
        customDeleteHandler?: (fields: FormFields) => Promise<void>,
    ) => {
        return (
            <Row hidden={!selected}>
                <Col>
                    <Row>
                        <Col className="">
                            {needSuperAdmin && !isSuperAdmin ? (
                                'If you need to delete this please contact Adam or Jeff on Discord.'
                            ) : (
                                <Button variant="danger" className="" onClick={() => doDelete(customDeleteHandler)}>
                                    Delete
                                </Button>
                            )}
                        </Col>
                    </Row>
                    {needSuperAdmin && isSuperAdmin ? (
                        <Row>
                            <Col>
                                <em className="text-danger">{warning}</em>
                            </Col>
                        </Row>
                    ) : (
                        ''
                    )}
                </Col>
            </Row>
        );
    };

    const saveButton = () => {
        return (
            <Button variant="primary" type="submit" value="Save Changes" disabled={!isDirty || !isValid}>
                Save Changes
            </Button>
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

    const renameCallback = async (e: RenameEvent): Promise<void> => {
        if (selected == undefined) {
            const msg = `You encountered a bug. The current selection is invalid in the middle of a rename operation.`;
            console.error(msg);
            setError(msg);
            return;
        }

        rename(selected, e, confirm)
            .then(async (u) => {
                try {
                    const f = await updatedFormFields(u);
                    formSubmit(f);
                } catch (e) {
                    console.error(e);
                }
            })
            .catch((e) => {
                console.error(e);
            });
    };

    const nameExists = async <T,>(name: string): Promise<boolean> => {
        if (apiConfig.nameExistsEndpoint) {
            return axios.get<T[]>(apiConfig.nameExistsEndpoint(name)).then((res) => {
                return res.data.length > 0;
            });
        } else {
            return Promise.resolve(false);
        }
    };

    const onDataChange = useCallback(async (t: T | undefined) => {
        const ff = await updatedFormFields(t);
        form.reset(ff as DefaultValues<FormFields>);
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, []);

    useEffect(() => {
        onDataChange(selected);
    }, [onDataChange, selected]);

    return {
        data: data,
        setData: setData,
        selected: selected,
        setSelected: setSelected,
        showRenameModal: showModal,
        setShowRenameModal: setShowModal,
        isValid: isValid,
        isDirty: isDirty,
        errors: errors,
        error: error,
        setError: setError,
        deleteResults: deleteResults,
        setDeleteResults: setDeleteResults,
        renameCallback: renameCallback,
        nameExists: nameExists,
        form: {
            formState: formState,
            ...form,
        },
        confirm: confirm,
        formSubmit: formSubmit,
        postUpdate: postUpdate,
        postDelete: postDelete,
        mainField: theMainField,
        deleteButton: deleteButton,
        saveButton: saveButton,
        isSuperAdmin: isSuperAdmin,
    };
};

export default useAdmin;
