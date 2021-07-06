import { constant, constFalse, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import React, { useEffect, useState } from 'react';
import { Button, Col, Form, Modal, Row } from 'react-bootstrap';
import { Controller, useForm } from 'react-hook-form';
import { HostSimple } from '../libs/api/apitypes';
import { GENUS, TaxonomyEntry, TaxonomyEntryNoParent } from '../libs/api/taxonomy';
import Typeahead from './Typeahead';

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
    const [genusKnown, setGenusKnown] = useState(false);
    const [genus, setGenus] = useState<TaxonomyEntryNoParent>();
    const [family, setFamily] = useState<TaxonomyEntryNoParent>();
    const [host, setHost] = useState<HostSimple>();
    const [name, setName] = useState('');
    const [description, setDescription] = useState('');

    const { register, getValues, control, watch } = useForm<FormFields>({
        mode: 'onBlur',
        defaultValues: {
            genus: 'Unknown',
            family: 'Unknown',
        },
    });

    const watchGenusKnown = watch('genusKnown', false);

    const resetState = () => {
        setGenus(undefined);
        setFamily(undefined);
        setHost(undefined);
        setName('');
        setDescription('');
    };

    const done = (cancel: boolean) => {
        if (cancel) {
            onClose(undefined);
            resetState();
            return;
        }

        if (family == undefined || genus == undefined || host == undefined) {
            throw new Error(
                `Somehow we have an undefined value for one of the family, genus, or host while trying to save the new undescribed species values.`,
            );
        }
        const fam = { ...family, parent: O.none };
        onClose({
            family: fam,
            genus: { ...genus, parent: O.of(fam) },
            host: host,
            name: name,
        });
        resetState();
    };

    const lookupFamily = (genus: TaxonomyEntryNoParent) => {
        return pipe(
            O.fromNullable(genera.find((g) => g.id === genus?.id)),
            O.chain((g) =>
                pipe(
                    g.parent,
                    O.map((p) => O.fromNullable(families.find((f) => f.id == p.id))),
                ),
            ),
            O.flatten,
            O.getOrElseW(constant(undefined)),
        );
    };

    useEffect(() => {
        if (genus || family || host || description) {
            const h = host ? `${host.name[0].toLocaleLowerCase()}-${host.name.split(' ')[1]}` : '';
            const newName = `${genus?.name ?? ''} ${h}-${description ? description : ''}`;
            setName(newName);
        } else {
            setName('');
        }
    }, [genus, family, description, host, getValues]);

    return (
        <Modal size="lg" show={show} onHide={() => done(true)}>
            <Modal.Header id="create-new-undescribed-gall" closeButton>
                <Modal.Title>Create a New Undescribed Gall Species</Modal.Title>
            </Modal.Header>
            <Modal.Body>
                <Form>
                    <Form.Group>
                        <Controller
                            name="genusKnown"
                            control={control}
                            render={({ field }) => (
                                <Form.Check
                                    {...register('genusKnown')}
                                    type="checkbox"
                                    label="Is this undescribed species part of a known Genus?"
                                    checked={genusKnown}
                                    onChange={(e) => {
                                        setGenusKnown(e.currentTarget.checked);
                                        setGenus(undefined);
                                        setFamily(undefined);
                                        field.onChange(e);
                                    }}
                                ></Form.Check>
                            )}
                        />
                        <Form.Label>Genus</Form.Label>
                        <Typeahead
                            name="genus"
                            control={control}
                            selected={genus ? [genus] : []}
                            onChange={(g) => {
                                setGenus(g[0]);
                                setFamily(lookupFamily(g[0]));
                            }}
                            disabled={!watchGenusKnown}
                            clearButton
                            options={genera.filter((g) => g.name.localeCompare('Unknown'))}
                            labelKey="name"
                        />
                        <Form.Text id="genusHelp" muted>
                            The genus, if it is known. Required if known.
                        </Form.Text>

                        <Form.Label>Family</Form.Label>
                        <Typeahead
                            name="family"
                            control={control}
                            selected={family ? [family] : []}
                            onChange={(f) => {
                                setFamily(f[0]);
                                const fam = families.find((fa) => fa.id === f[0]?.id);
                                const genus = fam
                                    ? genera.find((g) =>
                                          pipe(
                                              g.parent,
                                              O.map((p) => p.id === fam.id && g.name.localeCompare('Unknown') == 0),
                                              O.getOrElse(constFalse),
                                          ),
                                      )
                                    : undefined;
                                if (genus == undefined) {
                                    // need a new Unknown Genus attached to this Family
                                    setGenus({
                                        id: -1,
                                        description: '',
                                        name: 'Unknown',
                                        type: GENUS,
                                    });
                                } else {
                                    setGenus(genus);
                                }
                            }}
                            disabled={watchGenusKnown}
                            clearButton
                            options={families}
                            labelKey="name"
                        />
                        <Form.Text id="familyHelp" muted>
                            The family. If it is Unknown, select the Family Unknown from the list. Required.
                        </Form.Text>
                        <Form.Label>Type Host</Form.Label>
                        <Typeahead
                            name="host"
                            control={control}
                            selected={host ? [host] : []}
                            onChange={(h) => {
                                setHost(h[0]);
                            }}
                            clearButton
                            options={hosts}
                            labelKey="name"
                        />
                        <Form.Text id="hostHelp" muted>
                            The host that is the Type for this undecribed gall. Required.
                        </Form.Text>
                        <Form.Label>Description</Form.Label>
                        <Controller
                            name="description"
                            control={control}
                            render={({ field }) => (
                                <Form.Control
                                    value={description}
                                    onChange={(e) => {
                                        setDescription(e.currentTarget.value);
                                        field.onChange(e);
                                    }}
                                ></Form.Control>
                            )}
                        />
                        <Form.Text id="descriptionHelp" muted>
                            2 or 3 adjectives separated by dashes, e.g. red-bead-gall.
                        </Form.Text>
                        <Form.Label>Name</Form.Label>
                        <Controller
                            name="name"
                            control={control}
                            render={({ field }) => (
                                <Form.Control
                                    value={name}
                                    onChange={(e) => {
                                        setName(e.currentTarget.value);
                                        field.onChange(e);
                                    }}
                                ></Form.Control>
                            )}
                        />
                        <Form.Text id="nameHelp" muted>
                            You can edit this but it is suggested that you accept the computed value.
                        </Form.Text>
                    </Form.Group>
                </Form>
            </Modal.Body>
            <Modal.Footer>
                <div className="d-flex justify-content-end">
                    <Row>
                        <Col xs={4}>
                            <Button variant="primary" disabled={!name || !genus || !family || !host} onClick={() => done(false)}>
                                Done
                            </Button>
                        </Col>
                        <Col>
                            <Button
                                variant="secondary"
                                onClick={() => {
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
