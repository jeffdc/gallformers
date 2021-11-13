import React, { FocusEvent, KeyboardEvent } from 'react';
import {
    StringPropertyNames,
    Typeahead as RBTypeahead,
    TypeaheadModel,
    TypeaheadProps as RBTypeaheadProps,
} from 'react-bootstrap-typeahead';
import { Control, Controller, Path } from 'react-hook-form';

export type TypeaheadCustomOption = {
    customOption: boolean;
    name: string;
    id: string;
};

export type TypeaheadProps<T extends TypeaheadModel, FormFields> = Omit<RBTypeaheadProps<T>, 'id'> & {
    name: Path<FormFields>;
    control: Control<FormFields>;
    newSelectionPrefix?: string;
    rules?: Record<string, unknown>;
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
    rules,
    ...taProps
}: TypeaheadProps<T, FormFields>): JSX.Element => {
    return (
        <Controller
            control={control}
            name={name}
            rules={rules}
            render={({ field: { ref } }) => (
                <RBTypeahead
                    {...taProps}
                    ref={ref}
                    id={name}
                    // eslint-disable-next-line @typescript-eslint/ban-ts-comment
                    //@ts-ignore -- the typings for the component have a bug! Adding it here so all callers can avoid it.
                    newSelectionPrefix={newSelectionPrefix}
                />
            )}
        />
    );
};

export default Typeahead;
