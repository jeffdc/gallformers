import { HostDistinctFieldEnum, PrismaClient } from '@prisma/client';
import { Formik, FormikErrors, FormikTouched } from 'formik';
import { GetStaticProps } from 'next';
import { useRouter } from 'next/router';
import React from 'react';
import { Button, Col, Container, Form } from 'react-bootstrap';
import * as yup from 'yup';
import InfoTip from '../components/infotip';
import SearchFormField, { FieldValueType } from '../components/searchformfield';

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

type Props = {
    hosts: string[];
    locations: string[];
    textures: string[];
    colors: string[];
    alignments: string[];
    shapes: string[];
    cells: string[];
    walls: string[];
};

type FormProps = {
    handleSubmit: (e: React.FormEvent<HTMLFormElement>) => void;
    isSubmitting: boolean;
    touched: FormikTouched<FieldValueType>;
    errors: FormikErrors<FieldValueType>;
};

const Id = ({ hosts, locations, textures, colors, alignments, shapes, cells, walls }: Props): JSX.Element => {
    const router = useRouter();

    return (
        <div
            style={{
                marginBottom: '5%',
            }}
        >
            <Formik
                initialValues={{
                    hostName: '',
                    location: '',
                    detachable: '',
                    texture: '',
                    alignment: '',
                    walls: '',
                    cells: '',
                    color: '',
                    shape: '',
                }}
                validationSchema={schema}
                onSubmit={(values, { setSubmitting }) => {
                    setSubmitting(true);
                    router.push({
                        pathname: '/search',
                        query: {
                            host: values.hostName[0],
                            // we display 'unsure' to the user, but it is easier to treat it as an empty string from here on out
                            detachable: values.detachable[0] === 'unsure' ? '' : values.detachable[0],
                            alignment: values.alignment[0],
                            walls: values.walls[0],
                            locations: values.location !== '' ? JSON.stringify(values.location) : [],
                            textures: values.texture !== '' ? JSON.stringify(values.texture) : [],
                            color: values.color[0],
                            shape: values.shape[0],
                            cells: values.cells[0],
                        },
                    });
                    setSubmitting(false);
                }}
            >
                {({ handleSubmit, isSubmitting, touched, errors }: FormProps) => (
                    <Container className="pt-4">
                        <p>
                            <i>
                                To help ID a gall we need to gather some info. Fill in as much as you can but at a minimum we need
                                to know the host species.
                            </i>
                        </p>
                        <Form noValidate onSubmit={handleSubmit}>
                            <Form.Row>
                                <Form.Group as={Col} controlId="formHost">
                                    <Form.Label>Host Species (required)</Form.Label>
                                    <InfoTip id="host" text="The host plant that the gall is found on." />
                                    <SearchFormField
                                        name="hostName"
                                        touched={touched}
                                        errors={errors}
                                        options={hosts}
                                        placeholder="What is the host species?"
                                    />
                                </Form.Group>
                                <Form.Group as={Col} controlId="formLocation">
                                    <Form.Label>Location</Form.Label>
                                    <InfoTip
                                        id="location"
                                        text="Where on the host plant is the gall found? You can select multiple properties."
                                    />
                                    <SearchFormField
                                        name="location"
                                        touched={touched}
                                        errors={errors}
                                        options={locations}
                                        placeholder="Where is the gall located?"
                                        multiple
                                    />
                                </Form.Group>
                                <Form.Group as={Col} controlId="detachable">
                                    <Form.Label>Detachable</Form.Label>
                                    <InfoTip
                                        id="detachable"
                                        text="Can the gall be removed from the host plant or is it integral?"
                                    />
                                    <SearchFormField
                                        name="detachable"
                                        touched={touched}
                                        errors={errors}
                                        options={['unsure', 'yes', 'no']}
                                        placeholder="Is the gall detachable?"
                                    />
                                </Form.Group>
                            </Form.Row>
                            <Form.Row>
                                <Form.Group as={Col} controlId="formTexture">
                                    <Form.Label>Texture</Form.Label>
                                    <InfoTip id="texture" text="The overall look and feel of the gall." />
                                    <SearchFormField
                                        name="texture"
                                        touched={touched}
                                        errors={errors}
                                        options={textures}
                                        placeholder="What is the texture of the gall?"
                                        multiple
                                    />
                                </Form.Group>
                                <Form.Group as={Col} controlId="formAlignment">
                                    <Form.Label>Alignment</Form.Label>
                                    <InfoTip id="alignment" text="Is the gall straight up and down, leaning, etc.?" />
                                    <SearchFormField
                                        name="alignment"
                                        touched={touched}
                                        errors={errors}
                                        options={alignments}
                                        placeholder="What is the alignment of the gall?"
                                    />
                                </Form.Group>
                                <Form.Group as={Col} controlId="formWalls">
                                    <Form.Label>Walls</Form.Label>
                                    <InfoTip id="walls" text="If the gall is cut open what are the walls like?" />
                                    <SearchFormField
                                        name="walls"
                                        touched={touched}
                                        errors={errors}
                                        options={walls}
                                        placeholder="What are the walls of the gall like?"
                                    />
                                </Form.Group>
                            </Form.Row>
                            <Form.Row>
                                <Form.Group as={Col} controlId="formCells">
                                    <Form.Label>Cells</Form.Label>
                                    <InfoTip id="cells" text="How many cells (where the larvae are) are there in the gall?" />
                                    <SearchFormField
                                        name="cells"
                                        touched={touched}
                                        errors={errors}
                                        options={cells}
                                        placeholder="How many cells in the gall?"
                                    />
                                </Form.Group>
                                <Form.Group as={Col} controlId="formColor">
                                    <Form.Label>Color</Form.Label>
                                    <InfoTip id="color" text="What color is the gall?" />
                                    <SearchFormField
                                        name="color"
                                        touched={touched}
                                        errors={errors}
                                        options={colors}
                                        placeholder="What color is the gall?"
                                    />
                                </Form.Group>
                                <Form.Group as={Col} controlId="formShape">
                                    <Form.Label>Shape</Form.Label>
                                    <InfoTip id="shape" text="What is the shape of the gall?" />
                                    <SearchFormField
                                        name="shape"
                                        touched={touched}
                                        errors={errors}
                                        options={shapes}
                                        placeholder="What shape is the gall?"
                                    />
                                </Form.Group>
                            </Form.Row>
                            <Button variant="primary" type="submit" disabled={isSubmitting}>
                                Find Galls
                            </Button>
                        </Form>
                    </Container>
                )}
            </Formik>
        </div>
    );
};

// Use static so that this stuff can be built once on the server-side and then cached.
export const getStaticProps: GetStaticProps = async () => {
    const newdb = new PrismaClient();

    const h = await newdb.host.findMany({
        include: {
            hostspecies: {},
        },
        distinct: [HostDistinctFieldEnum.host_species_id],
    });
    const hosts = h
        .flatMap((h) => {
            if (h.hostspecies != null) return [h.hostspecies.name, h.hostspecies.commonnames];
            else return [];
        })
        .filter((h) => h)
        .sort();

    return {
        props: {
            hosts: hosts,
            locations: (await newdb.location.findMany({})).map((l) => l.location).sort(),
            colors: (await newdb.color.findMany({})).map((l) => l.color).sort(),
            shapes: (await newdb.shape.findMany({})).map((l) => l.shape).sort(),
            textures: (await newdb.texture.findMany({})).map((l) => l.texture).sort(),
            alignments: (await newdb.alignment.findMany({})).map((l) => l.alignment).sort(),
            walls: (await newdb.walls.findMany({})).map((l) => l.walls).sort(),
            cells: (await newdb.cells.findMany({})).map((l) => l.cells).sort(),
        },
        revalidate: 1,
    };
};

export default Id;
