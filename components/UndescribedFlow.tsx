import React from 'react';
import { Button, Col, Form, Modal, Row } from 'react-bootstrap';
import { useForm } from 'react-hook-form';
import { HostSimple } from '../libs/api/apitypes';
import { TaxonomyEntry } from '../libs/api/taxonomy';
import { genOptionsWithId } from '../libs/utils/forms';
import { extractGenus, lowercaseFirstLetter } from '../libs/utils/util';

type UndescribedData = {
    family: TaxonomyEntry;
    genus: TaxonomyEntry;
    name: string;
};

type Props = {
    show: boolean;
    onClose: (data: UndescribedData) => void;
    hosts: HostSimple[];
    genera: TaxonomyEntry[];
    families: TaxonomyEntry[];
};

type FormFields = {
    genusKnown: boolean;
    genus: string;
    family: string;
    host: string;
    description: string;
    name: string;
};

const UndescribedFlow = ({ show, onClose, hosts, genera, families }: Props): JSX.Element => {
    const { register, getValues, setValue, reset } = useForm<FormFields>({
        mode: 'onBlur',
        defaultValues: {
            genus: 'Unknown',
            family: 'Unknown',
        },
    });

    const done = () => {
        onClose({
            family: getValues().family,
            genus: getValues().genus,
            name: getValues().name,
        });
    };

    const onUnknownGenusChange = (checked: boolean) => {
        if (!checked) {
            reset({
                genusKnown: false,
                genus: 'Unknown',
                family: 'Unknown',
            });
        } else {
            reset({
                genusKnown: true,
                genus: '',
                family: '',
            });
        }
    };

    const computeName = (genus: string, host: string, description: string) => {
        return `${genus} ${lowercaseFirstLetter(host[0])}-${host?.split(' ')[1]}-${description}`;
    };

    const onChange = () => setValue('name', computeName(getValues().genus, getValues().host, getValues().description));

    return (
        <Modal size="lg" show={show} onHide={() => done()}>
            <Modal.Header id="new-dialog-title" closeButton>
                <Modal.Title>Create New Undescribed Gall Species</Modal.Title>
            </Modal.Header>
            <Modal.Body>
                <Form>
                    <Form.Group>
                        <Form.Check
                            type="checkbox"
                            label="Is this undescribed species part of a known Genus?"
                            ref={register}
                            name="genusKnown"
                            onChange={(e) => onUnknownGenusChange(e.currentTarget.checked)}
                        ></Form.Check>
                        <Form.Label>Genus</Form.Label>
                        <Form.Control as="select" ref={register} name="genus" onChange={onChange}>
                            {genOptionsWithId(genera)}
                        </Form.Control>
                        <Form.Label>Family</Form.Label>
                        <Form.Control as="select" ref={register} name="family">
                            {genOptionsWithId(families)}
                        </Form.Control>
                        <Form.Label>Type Host</Form.Label>
                        <Form.Control as="select" ref={register} name="host" onChange={onChange}>
                            {genOptionsWithId(hosts)}
                        </Form.Control>
                        <Form.Label>Description (2 or 3 adjectives separated by dashes, e.g. red-bead-gall)</Form.Label>
                        <Form.Control ref={register} name="description" onChange={onChange}></Form.Control>
                        <Form.Label>Name (you can edit this but it is suggested that you accept the computed value)</Form.Label>
                        <Form.Control ref={register} name="name"></Form.Control>
                    </Form.Group>
                </Form>
            </Modal.Body>
            <Modal.Footer>
                <div className="d-flex justify-content-end">
                    <Row>
                        <Col xs={4}>
                            <Button variant="primary" onClick={done}>
                                Done
                            </Button>
                        </Col>
                        <Col>
                            <Button variant="secondary" onClick={done}>
                                Cancel
                            </Button>
                        </Col>
                    </Row>
                </div>
            </Modal.Footer>
        </Modal>
    );
};

export default UndescribedFlow;
