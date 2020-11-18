import React from 'react';
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

export type BlurEvent = {
    target: { value: string };
};

export type ChangeEvent = string | TypeaheadCustomOption | null;

type Props = {
    name: string;
    placeholder: string;
    control: Control<Record<string, any>>;
    options: (string | null)[];
    multiple?: boolean;
    clearButton?: boolean;
    isInvalid?: boolean;
    allowNew?: boolean;
    newSelectionPrefix?: string;
    onChange?: (e: ChangeEvent[]) => void;
    onBlur?: (e: BlurEvent) => void;
};

/**
 * A wrapped version of react-bootstrap-typeahead that plays well with react-hook-form.
 */
const ControlledTypeahead = ({
    onChange,
    onBlur,
    options,
    placeholder,
    name,
    multiple,
    clearButton,
    control,
    isInvalid,
    allowNew,
    newSelectionPrefix,
}: Props): JSX.Element => {
    return (
        <Controller
            control={control}
            name={name}
            defaultValue={[]}
            render={(data) => (
                <Typeahead
                    onChange={(e: ChangeEvent[]) => {
                        if (onChange) onChange(e);

                        // deal with the fact that we are allowing new values - I could not divine a better way.
                        if (e && Array.isArray(e) && typeof e[0] === 'object') {
                            data.onChange(e[0]?.label);
                        } else {
                            data.onChange(e);
                        }
                    }}
                    onBlur={(e: BlurEvent) => {
                        if (onBlur) onBlur(e);
                        data.onBlur();
                    }}
                    selected={normalizeToArray(data.value)}
                    placeholder={placeholder}
                    id={name}
                    options={options}
                    multiple={multiple}
                    clearButton={clearButton}
                    isInvalid={isInvalid}
                    allowNew={allowNew}
                    newSelectionPrefix={newSelectionPrefix}
                />
            )}
        />
    );
};

export default ControlledTypeahead;
