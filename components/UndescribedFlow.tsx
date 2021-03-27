import React, { useState } from 'react';
import { Button, Col, Form, Modal, Row } from 'react-bootstrap';
import { useForm } from 'react-hook-form';
import { HostSimple } from '../libs/api/apitypes';
import { TaxonomyEntry } from '../libs/api/taxonomy';
import { genOptionsWithId } from '../libs/utils/forms';
import { lowercaseFirstLetter } from '../libs/utils/util';
import * as O from 'fp-ts/lib/Option';
import { constant, pipe } from 'fp-ts/lib/function';

export type UndescribedData = {
    family: TaxonomyEntry;
    genus: TaxonomyEntry;
    host: HostSimple;
    name: string;
};

type Props = {
    show: boolean;
    onClose: (data: UndescribedData | undefined) => void;
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
    const [genusUnknown, setGenusUnknown] = useState(true);
    const [formComplete, setFormComplete] = useState(false);

    const { register, getValues, setValue, reset } = useForm<FormFields>({
        mode: 'onBlur',
        defaultValues: {
            genus: 'Unknown',
            family: 'Unknown',
        },
    });

    const done = (cancel: boolean) => {
        if (cancel) {
            onClose(undefined);
            return;
        }

        const { family, genus, host, name } = getValues();
        const f = families.find((f) => f.name.localeCompare(family) == 0);
        const g = genera.find((g) => g.name.localeCompare(genus) == 0);
        const h = hosts.find((h) => h.name.localeCompare(host) == 0);
        if (f == undefined || g == undefined || h == undefined) {
            throw new Error(
                `Somehow we have an undefined value for one of the family, genus, or host while trying to save the new undescribed species values.`,
            );
        }
        onClose({
            family: f,
            genus: g,
            host: h,
            name: name,
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
        setFormComplete(false);
    };

    const computeName = (genus: string, host: string, description: string) => {
        return `${genus} ${lowercaseFirstLetter(host[0])}-${host?.split(' ')[1]}-${description}`;
    };

    const onChange = () => {
        const name = computeName(getValues().genus, getValues().host, getValues().description);
        setValue('name', name);
        setFormComplete(
            getValues().genus?.length > 0 &&
                getValues().family?.length > 0 &&
                getValues().host?.length > 0 &&
                getValues().name?.length > 0,
        );
    };

    const lookupFamily = (genus: string): string => {
        return pipe(
            O.fromNullable(genera.find((g) => g.name.localeCompare(genus) == 0)),
            O.chain((g) =>
                pipe(
                    g.parent,
                    O.map((p) => O.fromNullable(families.find((f) => f.id == p.id))),
                ),
            ),
            O.flatten,
            O.map((te) => te.name),
            O.getOrElse(constant('')),
        );
    };

    return (
        <Modal size="lg" show={show} onHide={() => done(true)}>
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
                        <Form.Control
                            as="select"
                            ref={register}
                            name="genus"
                            onChange={(e) => {
                                const unknown = e.currentTarget.value?.localeCompare('Unknown') == 0;
                                setGenusUnknown(unknown);
                                if (!unknown) {
                                    setValue('family', lookupFamily(e.currentTarget.value));
                                }
                                onChange();
                            }}
                        >
                            {genOptionsWithId(genera)}
                        </Form.Control>
                        <Form.Label>Family</Form.Label>
                        <Form.Control as="select" disabled={!genusUnknown} ref={register} name="family">
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
                            <Button variant="primary" disabled={!formComplete} onClick={() => done(false)}>
                                Done
                            </Button>
                        </Col>
                        <Col>
                            <Button variant="secondary" onClick={() => done(true)}>
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
