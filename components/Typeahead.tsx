import React, { FocusEvent, KeyboardEvent } from 'react';
import { Typeahead as RBTypeahead, AsyncTypeahead as RBAsyncTypeahead, UseAsyncProps } from 'react-bootstrap-typeahead';
import { TypeaheadComponentProps } from 'react-bootstrap-typeahead/types/components/Typeahead';
import { LabelKey, Option } from 'react-bootstrap-typeahead/types/types.js';
import { Control, Controller, FieldValues, Path } from 'react-hook-form';

export type TypeaheadProps<FormFields extends FieldValues> = TypeaheadComponentProps & {
    name: Path<FormFields>;
    control: Control<FormFields>;
    newSelectionPrefix?: string;
    rules?: Record<string, unknown>;
    onBlurT?: (e: FocusEvent<HTMLInputElement>) => void;
    onKeyDownT?: (e: KeyboardEvent<HTMLInputElement>) => void;
    // options: Option[];
    // onChange: (t: Option[]) => void;
    // selected: Option[];
    labelKey?: string | ((t: Option) => string);
};

export type TypeaheadLabelKey = LabelKey; //T extends object ? Option | ((option: T) => string) : never;

/**
 * A wrapped version of react-bootstrap-typeahead that handles new items and other misc stuff.
 */
const Typeahead = <T extends Option, FormFields extends FieldValues>({
    name,
    control,
    rules,
    options,
    onChange,
    selected,
    labelKey,
    ...taProps
}: TypeaheadProps<FormFields>): JSX.Element => {
    const theLK = !labelKey ? undefined : typeof labelKey === 'string' ? labelKey : (o: Option) => labelKey(o as T);
    return (
        <Controller
            control={control}
            name={name}
            rules={rules}
            render={({ field: { ref } }) => (
                <RBTypeahead
                    {...taProps}
                    labelKey={theLK}
                    options={options}
                    selected={selected}
                    onChange={(s: Option[]) => {
                        onChange ? onChange(s) : () => {};
                    }}
                    ref={ref}
                    id={name}
                />
            )}
        />
    );
};

export type AsyncTypeaheadProps<T, FormFields extends FieldValues> = Omit<UseAsyncProps, 'labelKey' | 'onChange' | 'selected'> & {
    name: Path<FormFields>;
    control: Control<FormFields>;
    rules?: Record<string, unknown>;
    onBlurT?: (e: FocusEvent<HTMLInputElement>) => void;
    onKeyDownT?: (e: KeyboardEvent<HTMLInputElement>) => void;
    options: T[];
    onChange: (t: T[]) => void;
    selected: T[];
    labelKey?: string | ((t: T) => string);
};

export const AsyncTypeahead = <T, FormFields extends FieldValues>({
    name,
    control,
    rules,
    options,
    onChange,
    selected,
    labelKey,
    ...taProps
}: AsyncTypeaheadProps<T, FormFields>): JSX.Element => {
    const theLK = !labelKey
        ? undefined
        : typeof labelKey === 'string'
          ? labelKey
          : (o: Option) => {
                return labelKey(o as T);
            };
    return (
        <Controller
            control={control}
            name={name}
            rules={rules}
            render={({ field: { ref } }) => (
                <RBAsyncTypeahead
                    {...taProps}
                    ref={ref}
                    id={name}
                    labelKey={theLK}
                    options={options as Option[]}
                    selected={selected as Option[]}
                    onChange={(s: Option[]) => {
                        onChange(s as T[]);
                    }}
                />
            )}
        />
    );
};

export default Typeahead;
