import React, { FocusEvent, KeyboardEvent } from 'react';
import { Typeahead } from 'react-bootstrap-typeahead';
import { Control, Controller } from 'react-hook-form';

// React Hook Forms and Typeahead sometimes do not agree on the selected value as a string or an array.
// This normalizes to an array.
function normalizeToArray<T>(v: T | T[] | undefined): T[] {
    if (v == undefined) return [];
    if (!Array.isArray(v)) return [v];
    return v;
}

type TypeaheadCustomOption = {
    customOption: boolean;
    label: string;
    id: string;
};

export type ControlledTypeaheadProps = {
    name: string;
    placeholder: string;
    control: Control<Record<string, unknown>>;
    options: string[];
    multiple?: boolean;
    clearButton?: boolean;
    isInvalid?: boolean;
    allowNew?: boolean;
    newSelectionPrefix?: string;
    disabled?: boolean;
    onChange?: (e: string[]) => void;
    onBlur?: (e: FocusEvent<HTMLInputElement>) => void;
    onInputChange?: (text: string, e: Event) => void;
    onKeyDown?: (e: KeyboardEvent<HTMLInputElement>) => void;
};

const isTypeaheadCustomOption = (e: string[] | TypeaheadCustomOption[]): e is TypeaheadCustomOption[] =>
    !!e && !!e[0] && typeof e[0] === 'object';
/**
 * A wrapped version of react-bootstrap-typeahead that plays well with react-hook-form.
 */
const ControlledTypeahead = ({
    onChange,
    onBlur,
    onInputChange,
    onKeyDown,
    options,
    placeholder,
    name,
    multiple,
    clearButton,
    control,
    isInvalid,
    allowNew,
    newSelectionPrefix,
    disabled,
}: ControlledTypeaheadProps): JSX.Element => {
    return (
        <Controller
            control={control}
            name={name}
            defaultValue={[]}
            render={(data) => (
                <Typeahead
                    onChange={(e: string[] | TypeaheadCustomOption[]) => {
                        // deal with the fact that we are allowing new values - I could not divine a better way.
                        if (isTypeaheadCustomOption(e)) {
                            const ee = (e[0] as TypeaheadCustomOption).label;
                            if (onChange) onChange([ee]);
                            data.onChange(ee);
                        } else {
                            if (onChange) onChange(e);
                            data.onChange(e);
                        }
                    }}
                    onInputChange={(text: string, e: Event) => {
                        if (onInputChange) onInputChange(text, e);
                    }}
                    onBlur={(e: Event) => {
                        //TODO how to deal with the fact that th Typeahead type here is only Event?
                        if (onBlur) onBlur((e as unknown) as FocusEvent<HTMLInputElement>);
                        data.onBlur();
                    }}
                    onKeyDown={(e: Event) => {
                        //TODO how to deal with the fact that th Typeahead type here is only Event?
                        if (onKeyDown && e) onKeyDown((e as unknown) as KeyboardEvent<HTMLInputElement>);
                    }}
                    //TODO how to type data.value?
                    selected={normalizeToArray(data.value)}
                    placeholder={placeholder}
                    id={name}
                    options={options}
                    multiple={multiple}
                    clearButton={clearButton}
                    isInvalid={isInvalid}
                    allowNew={allowNew}
                    // TODO: why when I added the new typings did this break? It functions correctly but types do not line up.
                    // eslint-disable-next-line @typescript-eslint/ban-ts-comment
                    // @ts-ignore
                    newSelectionPrefix={newSelectionPrefix}
                    disabled={disabled}
                />
            )}
        />
    );
};

export default ControlledTypeahead;
