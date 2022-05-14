import React, { FocusEvent, KeyboardEvent } from 'react';
import { Typeahead as RBTypeahead } from 'react-bootstrap-typeahead';
import { TypeaheadComponentProps } from 'react-bootstrap-typeahead/types/components/Typeahead';
import { LabelKey, Option } from 'react-bootstrap-typeahead/types/types';
import { Control, Controller, Path } from 'react-hook-form';

export type TypeaheadCustomOption = {
    customOption: boolean;
    name: string;
    id: string;
};

export type TypeaheadProps<T, FormFields> = Omit<TypeaheadComponentProps, 'labelKey' | 'options' | 'onChange' | 'selected'> & {
    name: Path<FormFields>;
    control: Control<FormFields>;
    newSelectionPrefix?: string;
    rules?: Record<string, unknown>;
    onBlurT?: (e: FocusEvent<HTMLInputElement>) => void;
    onKeyDownT?: (e: KeyboardEvent<HTMLInputElement>) => void;
    options: T[];
    onChange: (t: T[]) => void;
    selected: T[];
    labelKey?: string | ((t: T) => string);
};

export type TypeaheadLabelKey = LabelKey; //T extends object ? Option | ((option: T) => string) : never;

/**
 * A wrapped version of react-bootstrap-typeahead that handles new items and other misc stuff.
 */
const Typeahead = <T, FormFields>({
    name,
    control,
    // newSelectionPrefix,
    rules,
    options,
    onChange,
    selected,
    labelKey,
    ...taProps
}: TypeaheadProps<T, FormFields>): JSX.Element => {
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
                <RBTypeahead
                    {...taProps}
                    labelKey={theLK}
                    options={options}
                    selected={selected}
                    onChange={(s: Option[]) => {
                        onChange(s as T[]);
                    }}
                    ref={ref}
                    id={name}
                    // eslint-disable-next-line @typescript-eslint/ban-ts-comment
                    //@ts-ignore -- the typings for the component have a bug! Adding it here so all callers can avoid it.
                    // newSelectionPrefix={newSelectionPrefix}
                />
            )}
        />
    );
};

export default Typeahead;
