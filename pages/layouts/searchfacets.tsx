import { Formik, FormikErrors, FormikTouched } from 'formik';
import { useRouter } from 'next/router';
import React, { useState } from 'react';
import { Col, Container, Form } from 'react-bootstrap';
import * as yup from 'yup';
import SearchFormField, { FieldValueType } from '../../components/searchformfield';
import { hasProp } from '../../libs/util';

export type SearchInitialProps = {
    hosts: string[],
    locations: string[],
    textures: string[],
    colors: string[],
    alignments: string[],
    shapes: string[],
    cells: string[],
    walls: string[]
};

export type SearchQuery = {
    host: string,
    detachable?: string,
    alignment?: string,
    walls?: string,
    locations?: string[],
    textures?: string[],
    color?: string,
    shape?: string,
    cells?: string
};

export type SearchProps = SearchInitialProps & {
    doSearch: (q: SearchQuery) => void
}

const schema = yup.object({
    hostName: yup.string().required('You must provide a host name.'),
    location: yup.string(),
    detachable: yup.string(),
    texture: yup.string(),
    alignment: yup.string(),
    walls: yup.string(),
    cells: yup.string(),
    color: yup.string(),
    shape: yup.string(),
});

type FormProps = {
    handleSubmit: (e: React.FormEvent<HTMLFormElement>) => void,
    isSubmitting: boolean,
    touched: FormikTouched<FieldValueType>,
    errors: FormikErrors<FieldValueType>
}

//{doSearch, hosts, locations, textures, colors, alignments, shapes, cells, walls}
export const SearchFacets = ({doSearch, hosts, locations, textures, colors, alignments, shapes, cells, walls}: SearchProps):
        JSX.Element => {
    const router = useRouter();
    const query = router.query as SearchQuery;
    const [q, setQ] = useState(query);

    // this helper seems to be needed as setting real initial values on the typeahead via Formik causes an error :(
    const initalValue = (field: string, multiple = false): string | string[] => {
        const prop = hasProp(query, field);
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        return prop && (query as any)[field] ? (query as any)[field]: (multiple ? [] : '')
    }

    const onChange = (name: string, selected: string | string[]) => {
        const newQ: SearchQuery = { ...q };
        if (hasProp(newQ, name)) {
            newQ[name] = selected;
        }
        setQ(newQ);
        doSearch(q);
    };

    return (
        <Container className='fixed-left border p-0 mt-2'>
            <Formik
                // initialValues={ {...query} } // <-- this does not work and I got stuck trying to figure out why.
                initialValues={{ host: '', locations: '', textures: '', color: '', alignment: '', shape: '', cells: '', walls: '', detachable: '' }}
                validationSchema={schema}
                onSubmit={ (values, {setSubmitting}) => {
                    setSubmitting(true);
                    setSubmitting(false);
                }}
            >
            {({
                handleSubmit,
                touched,
                errors,
            }: FormProps ) => (
                <Container className="p-0">
                    <Form noValidate onSubmit={handleSubmit}>
                            <Form.Group as={Col} controlId="formHost">
                                <Form.Label>Host Species</Form.Label>
                                {/* <InfoTip id="host" text="The host plant that the gall is found on." /> */}
                                <SearchFormField 
                                    name="host"
                                    touched={touched}
                                    errors={errors}
                                    options={hosts}
                                    placeholder="Gall host?"
                                    defaultInputValue={ initalValue('host') as string }
                                    onChange={onChange}
                                />                        
                            </Form.Group>
                            <Form.Group as={Col} controlId="formLocation">
                                <Form.Label>Location</Form.Label>
                                {/* <InfoTip id="location" text="Where on the host plant is the gall found? You can select multiple properties." /> */}
                                <SearchFormField 
                                    name="locations"
                                    touched={touched}
                                    errors={errors}
                                    options={locations}
                                    placeholder="Gall location?"
                                    multiple
                                    defaultInputValue={ initalValue('locations') as string[] }
                                    onChange={onChange}
                                />
                            </Form.Group>
                            <Form.Group as={Col} controlId="detachable">
                                <Form.Label>Detachable</Form.Label>
                                {/* <InfoTip id="detachable" text="Can the gall be removed from the host plant or is it integral?" /> */}
                                <SearchFormField 
                                    name="detachable"
                                    touched={touched}
                                    errors={errors}
                                    options={['unsure', 'yes', 'no']}
                                    placeholder="Gall detachable?"
                                    defaultInputValue={ initalValue('detachable') as string }
                                    onChange={onChange}
                                />
                            </Form.Group>
                            <Form.Group as={Col} controlId="formTexture">
                                <Form.Label>Texture</Form.Label>
                                {/* <InfoTip id="texture" text="The overall look and feel of the gall." /> */}
                                <SearchFormField 
                                    name="textures"
                                    touched={touched}
                                    errors={errors}
                                    options={textures}
                                    placeholder="Gall texture?"
                                    multiple
                                    defaultInputValue={ initalValue('textures') as string[] }
                                    onChange={onChange}
                                />
                            </Form.Group>   
                            <Form.Group as={Col} controlId="formAlignment">
                                <Form.Label>Alignment</Form.Label>
                                {/* <InfoTip id="alignment" text="Is the gall straight up and down, leaning, etc.?" /> */}
                                <SearchFormField 
                                    name="alignment"
                                    touched={touched}
                                    errors={errors}
                                    options={alignments}
                                    placeholder="Gall alignment?"
                                    defaultInputValue={ initalValue('alignment') as string }
                                    onChange={onChange}
                                />
                            </Form.Group>
                            <Form.Group as={Col} controlId="formWalls">
                                <Form.Label>Walls</Form.Label>
                                {/* <InfoTip id="walls" text="If the gall is cut open what are the walls like?" /> */}
                                <SearchFormField 
                                    name="walls"
                                    touched={touched}
                                    errors={errors}
                                    options={walls}
                                    placeholder="Gall walls?"
                                    defaultInputValue={ initalValue('walls') as string }
                                    onChange={onChange}
                               />
                            </Form.Group>
                            <Form.Group as={Col} controlId="formCells">
                                <Form.Label>Cells</Form.Label>
                                {/* <InfoTip id="cells" text="How many cells (where the larvae are) are there in the gall?" /> */}
                                <SearchFormField 
                                    name="cells"
                                    touched={touched}
                                    errors={errors}
                                    options={cells}
                                    placeholder="Gall cells?"
                                    defaultInputValue={ initalValue('cells') as string }
                                    onChange={onChange}
                                />
                            </Form.Group>   
                            <Form.Group as={Col} controlId="formColor">
                                <Form.Label>Color</Form.Label>
                                {/* <InfoTip id="color" text="What color is the gall?" /> */}
                                <SearchFormField 
                                    name="color"
                                    touched={touched}
                                    errors={errors}
                                    options={colors}
                                    placeholder="Gall color?"
                                    defaultInputValue={ initalValue('color') as string }
                                    onChange={onChange}
                                />
                            </Form.Group>
                            <Form.Group as={Col} controlId="formShape">
                                <Form.Label>Shape</Form.Label>
                                {/* <InfoTip id="shape" text="What is the shape of the gall?" /> */}
                                <SearchFormField 
                                    name="shape"
                                    touched={touched}
                                    errors={errors}
                                    options={shapes}
                                    placeholder="Gall shape?"
                                    defaultInputValue={ initalValue('shape') as string }
                                    onChange={onChange}
                                />
                            </Form.Group>
                    </Form>
                </Container> 
            )}
        </Formik>
        </Container>
    )
};

export default SearchFacets;