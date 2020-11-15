import { Field, FieldConfig, FormikErrors, FormikProps, FormikTouched } from 'formik';
import { Typeahead } from 'react-bootstrap-typeahead';

export type FieldValueType = string | string[];
type Props = {
    name: string;
    touched: FormikTouched<FieldValueType>;
    errors: FormikErrors<FieldValueType>;
    options: Array<string>;
    placeholder: string;
    multiple?: boolean;
    defaultInputValue?: string | string[];
    onChange?: (name: string, selected: string | Array<string>) => void;
};

// A form field used on the search page. It uses Formix and Typeahead.
// Must wrap the Typeahead in a Formix Field so that we can access Formix managed state
const SearchFormField = ({
    name,
    touched,
    errors,
    options,
    placeholder,
    multiple,
    defaultInputValue,
    onChange,
}: Props): JSX.Element => {
    if (name == undefined || name == null) {
        throw new Error('Name must be defined.');
    }

    return (
        <>
            <Field name={name}>
                {({ field, form }: { field: FieldConfig; form: FormikProps<FieldValueType> }) => (
                    <Typeahead
                        id={name}
                        // labelKey={name}
                        onChange={(v: FieldValueType) => {
                            if (onChange) onChange(name, v);
                            form.setFieldValue(name, v);
                        }}
                        options={options}
                        selected={field.value ? field.value : []}
                        placeholder={placeholder}
                        // eslint-disable-next-line @typescript-eslint/no-explicit-any
                        isInvalid={!!(form.errors as any)[name]}
                        multiple={multiple}
                        defaultInputValue={defaultInputValue ? defaultInputValue : ''}
                    />
                )}
            </Field>
            {
                // eslint-disable-next-line @typescript-eslint/no-explicit-any
                (touched as any)[name] && (errors as any)[name] ? <div>{(errors as any)[name]}</div> : null
            }
        </>
    );
};

export default SearchFormField;
