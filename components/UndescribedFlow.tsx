import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import React from 'react';
import { Button, Col, Form, Modal, Row } from 'react-bootstrap';
import { Controller, useForm } from 'react-hook-form';
import { HostSimple } from '../libs/api/apitypes';
import { TaxonomyEntry } from '../libs/api/taxonomy';
import { genOptionsWithId } from '../libs/utils/forms';
import { lowercaseFirstLetter } from '../libs/utils/util';

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
    // const [genusUnknown, setGenusKnown] = useState(true);

    const { register, getValues, setValue, reset, control, watch } = useForm<FormFields>({
        mode: 'onBlur',
        defaultValues: {
            genus: 'Unknown',
            family: 'Unknown',
        },
    });

    const watchName = watch('name', '');
    const watchGenusKnown = watch('genusKnown', false);

    const done = (cancel: boolean) => {
        if (cancel) {
            onClose(undefined);
            return;
        }

        const { genusKnown, family, genus, host, name } = getValues();
        const f = families.find((f) => f.name.localeCompare(family) == 0);
        const g = genera.find((g) => g.name.localeCompare(genusKnown ? genus : 'Unknown') == 0);
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

    const onKnownGenusChange = (checked: boolean) => {
        if (!checked) {
            reset({
                genusKnown: checked,
                genus: 'Unknown',
                family: 'Unknown',
            });
        } else {
            reset({
                genusKnown: checked,
                genus: '',
                family: '',
            });
        }
    };

    const computeName = (genus: string, host: string, description: string) => {
        const h = host ? `${lowercaseFirstLetter(host[0])}-${host?.split(' ')[1]}` : '';
        return `${getValues().genusKnown ? genus : 'Unknown'} ${h}-${description ? description : ''}`;
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
                            {...register('genusKnown')}
                            type="checkbox"
                            label="Is this undescribed species part of a known Genus?"
                            onChange={(e) => {
                                onKnownGenusChange(e.currentTarget.checked);
                            }}
                        ></Form.Check>
                        <Form.Label>Genus</Form.Label>
                        <Controller
                            name="genus"
                            control={control}
                            render={({ field }) => (
                                <Form.Control
                                    as="select"
                                    onChange={(e) => {
                                        if (e.currentTarget.value) {
                                            setValue('family', lookupFamily(e.currentTarget.value));
                                        }
                                        const name = computeName(
                                            e.currentTarget.value,
                                            getValues().host,
                                            getValues().description,
                                        );
                                        setValue('name', name);
                                        field.onChange(e);
                                    }}
                                    disabled={!watchGenusKnown}
                                >
                                    {genOptionsWithId(genera.filter((g) => g.name.localeCompare('Unknown')))}
                                </Form.Control>
                            )}
                        />
                        <Form.Label>Family</Form.Label>
                        <Form.Control {...register('family')} as="select" readOnly={watchGenusKnown}>
                            {genOptionsWithId(families)}
                        </Form.Control>
                        <Form.Label>Type Host</Form.Label>
                        <Controller
                            name="host"
                            control={control}
                            render={({ field }) => (
                                <Form.Control
                                    as="select"
                                    onChange={(e) => {
                                        const name = computeName(
                                            getValues().genus,
                                            e.currentTarget.value,
                                            getValues().description,
                                        );
                                        setValue('name', name);
                                        field.onChange(e);
                                    }}
                                >
                                    {genOptionsWithId(hosts)}
                                </Form.Control>
                            )}
                        />
                        <Form.Label>Description (2 or 3 adjectives separated by dashes, e.g. red-bead-gall)</Form.Label>
                        <Controller
                            name="description"
                            control={control}
                            render={({ field }) => (
                                <Form.Control
                                    onChange={(e) => {
                                        // eslint-disable-next-line prettier/prettier
                                        const name = computeName(
                                            getValues().genus,
                                            getValues().host,
                                            e.currentTarget.value,
                                        );
                                        setValue('name', name);
                                        field.onChange(e);
                                    }}
                                ></Form.Control>
                            )}
                        />
                        <Form.Label>Name (you can edit this but it is suggested that you accept the computed value)</Form.Label>
                        <Form.Control {...register('name')}></Form.Control>
                    </Form.Group>
                </Form>
            </Modal.Body>
            <Modal.Footer>
                <div className="d-flex justify-content-end">
                    <Row>
                        <Col xs={4}>
                            <Button variant="primary" disabled={!watchName} onClick={() => done(false)}>
                                Done
                            </Button>
                        </Col>
                        <Col>
                            <Button
                                variant="secondary"
                                onClick={() => {
                                    reset();
                                    return done(true);
                                }}
                            >
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
