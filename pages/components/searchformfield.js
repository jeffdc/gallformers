import { Typeahead } from 'react-bootstrap-typeahead';
import { Field } from 'formik';

// A form field used on the search page. It uses Formix and Typeahead.
// Must wrap the Typeahead in a Formix Field so that we can access Formix managed state
const SearchFormField = ( {name, touched, errors, options, placeholder} ) => {
    return (
        <>
            <Field name={name}>
                {({ field, form }) =>
                    <Typeahead
                        id={name}
                        labelKey={name}
                        onChange={v => form.setFieldValue(name, v)}
                        options={options}
                        value={field.value}
                        placeholder={placeholder}
                        isInvalid={!!form.errors[name]}
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