import { Field, FieldInputProps, FormikErrors, FormikProps, FormikTouched } from 'formik';
import { Typeahead, TypeaheadModel } from 'react-bootstrap-typeahead';
 
type Props = {
    name: string,
    touched: FormikTouched<TypeaheadModel>,
    errors: FormikErrors<TypeaheadModel>,
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
                {({ field, form }: {field: FieldInputProps<TypeaheadModel>, form:FormikProps<TypeaheadModel>}) =>
                    <Typeahead
                        id={name}
                        // this makes no sense to me why this has to be cast to any :(
                        labelKey={name as any}
                        onChange={v => form.setFieldValue(name, v)}
                        options={options}
                        // i am unsure what is going on here. if i use value it works but will not compile as strict TS, 
                        // if use selected it breaks in multiple ways. It has something to do with multiple selections vs
                        // single selections and the way the data is managed in the form vs in the Typeahead component.
                        // selected={[field.value]}
                        value={field.value}
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