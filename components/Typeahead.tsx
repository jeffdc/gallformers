import React, { FocusEvent, KeyboardEvent } from 'react';
import {
    StringPropertyNames,
    Typeahead as RBTypeahead,
    TypeaheadModel,
    TypeaheadProps as RBTypeaheadProps,
} from 'react-bootstrap-typeahead';
import { Control, Controller } from 'react-hook-form';

export type TypeaheadCustomOption = {
    customOption: boolean;
    name: string;
    id: string;
};

export type TypeaheadProps<T extends TypeaheadModel, FormFields> = Omit<RBTypeaheadProps<T>, 'id'> & {
    name: Path<FormFields>;
    control: Control<FormFields>;
    newSelectionPrefix?: string;
    onBlurT?: (e: FocusEvent<HTMLInputElement>) => void;
    onKeyDownT?: (e: KeyboardEvent<HTMLInputElement>) => void;
};

// eslint-disable-next-line @typescript-eslint/ban-types
export type TypeaheadLabelKey<T> = T extends object ? StringPropertyNames<T> | ((option: T) => string) : never;

/**
 * A wrapped version of react-bootstrap-typeahead that handles new items and other misc stuff.
 */
const Typeahead = <T extends TypeaheadModel, FormFields>({
    name,
    control,
    newSelectionPrefix,
    onBlurT,
    onKeyDownT,
    ...taProps
}: TypeaheadProps<T, FormFields>): JSX.Element => {
    return (
        <Controller
            control={control}
            name={name}
            render={({ field: { onChange, onBlur, value, ref } }) => (
                <RBTypeahead
                    {...taProps}
                    ref={ref}
                    id={name}
                    // selected={value as T[]}
                    // onChange={(e) => {
                    //     if (taProps.onChange) taProps.onChange(e);
                    //     onChange(e);
                    // }}
                    // onBlur={(e) => {
                    //     if (onBlurT) onBlurT((e as unknown) as FocusEvent<HTMLInputElement>);
                    //     if (taProps.onBlur) taProps.onBlur(e);
                    //     onBlur();
                    // }}
                    // onKeyDown={(e) => {
                    //     if (onKeyDownT) onKeyDownT((e as unknown) as KeyboardEvent<HTMLInputElement>);
                    //     if (taProps.onKeyDown) taProps.onKeyDown(e);
                    // }}
                    // eslint-disable-next-line @typescript-eslint/ban-ts-comment
                    //@ts-ignore -- the typings for the component have a bug! Adding it here so all callers can avoid it.
                    newSelectionPrefix={newSelectionPrefix}
                />
            )}
        />
    );
};

export default Typeahead;
