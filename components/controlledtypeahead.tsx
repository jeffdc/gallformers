import React, { FocusEvent, KeyboardEvent } from 'react';
import { Typeahead, TypeaheadModel, TypeaheadProps } from 'react-bootstrap-typeahead';
import { Control, Controller } from 'react-hook-form';
import { hasProp } from '../libs/utils/util';

export type TypeaheadCustomOption = {
    customOption: boolean;
    name: string;
    id: string;
};

export type ControlledTypeaheadProps<T extends TypeaheadModel> = TypeaheadProps<T> & {
    name: string;
    /* eslint-disable @typescript-eslint/no-explicit-any */
    control: Control<Record<string, any>>;
    newSelectionPrefix?: string;
    onChangeWithNew?: (selected: T[], isNew: boolean) => void;
    onBlurT?: (e: FocusEvent<HTMLInputElement>) => void;
    onKeyDownT?: (e: KeyboardEvent<HTMLInputElement>) => void;
};

/**
 * A wrapped version of react-bootstrap-typeahead that plays well with react-hook-form.
 */
const ControlledTypeahead = <T extends TypeaheadModel>({
    name,
    control,
    newSelectionPrefix,
    onChangeWithNew,
    onBlurT,
    onKeyDownT,
    ...taProps
}: ControlledTypeaheadProps<T>): JSX.Element => {
    return (
        <Controller
            control={control}
            name={name}
            defaultValue={[]}
            render={(data) => (
                <Typeahead
                    {...taProps}
                    defaultSelected={[]}
                    selected={Array.isArray(data.value) ? data.value : [data.value]}
                    id={taProps.id ? taProps.id : name}
                    onChange={(selected: T[]) => {
                        const isNew = selected.length > 0 && hasProp(selected[0], 'customOption');
                        if (onChangeWithNew) onChangeWithNew(selected, isNew);
                        // make sure to let the Controller know as well
                        data.onChange(selected);
                        if (taProps.onChange) taProps.onChange(selected);
                    }}
                    onBlur={(e) => {
                        if (onBlurT) onBlurT((e as unknown) as FocusEvent<HTMLInputElement>);
                        data.onBlur();
                        if (taProps.onBlur) taProps.onBlur(e);
                    }}
                    onKeyDown={(e) => {
                        if (onKeyDownT) onKeyDownT((e as unknown) as KeyboardEvent<HTMLInputElement>);
                        if (taProps.onKeyDown) taProps.onKeyDown(e);
                    }}
                    // eslint-disable-next-line @typescript-eslint/ban-ts-comment
                    //@ts-ignore -- the typings for the component have a bug! Adding it here so all callers can avoid it.
                    newSelectionPrefix={newSelectionPrefix}
                />
            )}
        />
    );
};

export default ControlledTypeahead;
