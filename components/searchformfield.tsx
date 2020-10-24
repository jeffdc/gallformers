import { Field, FieldInputProps, FormikProps } from 'formik';
import { Typeahead } from 'react-bootstrap-typeahead';

type Props = {
    name: string,
    touched: any,
    errors: any,  // not sure how to do better than this
    options: Array<string>,
    placeholder: string,
    multiple?: boolean
}

// A form field used on the search page. It uses Formix and Typeahead.
// Must wrap the Typeahead in a Formix Field so that we can access Formix managed state
function SearchFormField( {name, touched, errors, options, placeholder, multiple}: Props) {
    if (name == undefined || name == null) {
        throw new Error('Name must be defined.')
    }

        // I tried to genericize the component on V, however I could not get past the fact that the Typeahead
        // componenet can not be typed to some type V. This ends up with the field form values being typed with 'any'.
        return (
        <>
            <Field name={name}>
                {({ field, form }: {field: FieldInputProps<any>, form:FormikProps<any>}) =>
                    <Typeahead
                        id={name}
                        // this makes no sense to me why this has to be cast to any :(
                        labelKey={name as any}
                        onChange={v => form.setFieldValue(name, v)}
                        options={options}
                        // i am unsure what is going on here. if i use value it works but will not compile as strict TS, 
                        // if use selected it breaks in multiple ways. I thas something to do with multiple selections vs
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