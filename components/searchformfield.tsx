import { Field } from 'formik';
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
const SearchFormField = ( {name, touched, errors, options, placeholder, multiple}: Props) => {
    if (name == undefined || name == null) {
        throw new Error('Name must be defined.')
    }
    return (
        <>
            <Field name={name}>
                {({ field, form }: {field:any, form:any}) =>
                    <Typeahead
                        id={name}
                        labelKey={name as any}
                        onChange={v => form.setFieldValue(name, v)}
                        options={options}
                        selected={field.value}
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