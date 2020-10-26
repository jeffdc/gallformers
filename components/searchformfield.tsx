import { Field, FieldConfig, FormikErrors, FormikProps, FormikTouched } from 'formik';
import { Typeahead } from 'react-bootstrap-typeahead';

export type FieldValueType = string | string[];
type Props = {
    name: string,
    touched: FormikTouched<FieldValueType>,
    errors: FormikErrors<FieldValueType>,
    options: Array<string>,
    placeholder: string,
    multiple?: boolean
}

// A form field used on the search page. It uses Formix and Typeahead.
// Must wrap the Typeahead in a Formix Field so that we can access Formix managed state
const SearchFormField = ( {name, touched, errors, options, placeholder, multiple}: Props): JSX.Element => {
    if (name == undefined || name == null) {
        throw new Error('Name must be defined.')
    }

    return (
        <>
            <Field name={name}>
                {({ field, form }: {field: FieldConfig, form: FormikProps<FieldValueType>}) =>
                    <Typeahead
                        id={name}
                        // labelKey={name}
                        onChange={(v: FieldValueType) => form.setFieldValue(name, v)}
                        options={options}
                        selected={field.value ? field.value : []}
                        placeholder={placeholder}
                        isInvalid={!!form.errors[name]}
                        multiple={multiple}
                />                                    
                }
            </Field>
            { touched[name] && errors[name] ? (
                <div>{errors[name]}</div>
            ) : null }
        </>
    )
};
  
export default SearchFormField;