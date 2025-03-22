import axios from 'axios';
import { constant, constFalse, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { useEffect, useState } from 'react';
import { Alert, Button, Col, Form, Modal, Row } from 'react-bootstrap';
import { Controller, useForm } from 'react-hook-form';
import { GallSimple, HostSimple, TaxonomyEntry, TaxonomyEntryNoParent, TaxonomyTypeValues } from '../libs/api/apitypes';
import { AsyncTypeahead, Typeahead } from 'react-bootstrap-typeahead';

export type UndescribedData = {
    family: TaxonomyEntry;
    genus: TaxonomyEntry;
    host: HostSimple;
    name: string;
};

type Props = {
    show: boolean;
    onClose: (data: UndescribedData | undefined) => void;
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

const UndescribedFlow = ({ show, onClose, genera, families }: Props): JSX.Element => {
    const [genusKnown, setGenusKnown] = useState(false);
    const [genus, setGenus] = useState<TaxonomyEntryNoParent>();
    const [family, setFamily] = useState<TaxonomyEntryNoParent>();
    const [host, setHost] = useState<HostSimple>();
    const [name, setName] = useState('');
    const [description, setDescription] = useState('');
    const [errMessage, setErrMessage] = useState('');
    const [hosts, setHosts] = useState<HostSimple[]>([]);
    const [isLoading, setIsLoading] = useState(false);

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

        // The guard against this is that the Done button is disabled until all of these have a value, but just in case.
        if (family == undefined || genus == undefined || host == undefined) {
            throw new Error(
                `Somehow we have an undefined value for one of the family, genus, or host while trying to save the new undescribed species values.`,
            );
        }

        void axios.get<GallSimple[]>(`/api/gall?name=${name}`).then((res) => {
            if (res.data.filter((g) => g.name === name).length > 0) {
                setErrMessage(
                    `The name you have chosen, (${name}), already exists in the database. Either chose a new name or Cancel out of this and edit the existing gall.`,
                );
            } else {
                const fam = { ...family, parent: O.none };
                onClose({
                    family: fam,
                    genus: { ...genus, parent: O.of(fam) },
                    host: host,
                    name: name,
                });
                resetState();
            }
        });
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

    const handleHostSearch = (s: string) => {
        setIsLoading(true);

        axios
            .get<HostSimple[]>(`/api/host?q=${s}&simple`)
            .then((resp) => {
                setHosts(resp.data);
                setIsLoading(false);
            })
            .catch((e) => {
                console.error(e);
            });
    };

    return (
        <Modal size="lg" show={show} onHide={() => done(true)}>
            <Modal.Header id="create-new-undescribed-gall" closeButton>
                <Modal.Title>Create a New Undescribed Gall Species</Modal.Title>
            </Modal.Header>
            <Modal.Body>
                <Form>
                    <Row>
                        <Col>
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
                        </Col>
                    </Row>
                    <Row>
                        <Col>
                            <Form.Label>Genus</Form.Label>
                            <Typeahead
                                id="genus"
                                defaultSelected={genus ? [genus] : []}
                                onChange={(g) => {
                                    const genus = g[0] as TaxonomyEntryNoParent;
                                    setGenus(genus);
                                    setFamily(lookupFamily(genus));
                                }}
                                disabled={!watchGenusKnown}
                                clearButton
                                options={genera.filter((g) => g.name.localeCompare('Unknown'))}
                                labelKey="name"
                            />
                            <Form.Text id="genusHelp" muted>
                                The genus, if it is known. Required if known.
                            </Form.Text>
                        </Col>
                    </Row>

                    <Row>
                        <Col>
                            <Form.Label>Family</Form.Label>
                            <Typeahead
                                id="family"
                                defaultSelected={family ? [family] : []}
                                onChange={(f) => {
                                    const family = f[0] as TaxonomyEntryNoParent;
                                    setFamily(family);
                                    const fam = families.find((fa) => fa.id === family?.id);
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
                                            type: TaxonomyTypeValues.GENUS,
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
                        </Col>
                    </Row>

                    <Row>
                        <Col>
                            <Form.Label>Type Host</Form.Label>
                            <AsyncTypeahead
                                id="host"
                                defaultSelected={host ? [host] : []}
                                onChange={(h) => {
                                    setHost(h[0] as HostSimple);
                                }}
                                clearButton
                                options={hosts}
                                labelKey="name"
                                isLoading={isLoading}
                                onSearch={handleHostSearch}
                            />
                            <Form.Text id="hostHelp" muted>
                                The host that is the Type for this undescribed gall. Required.
                            </Form.Text>
                        </Col>
                    </Row>

                    <Row>
                        <Col>
                            <Form.Label>Description</Form.Label>
                            <Form.Control
                                id="description"
                                value={description}
                                onChange={(e) => {
                                    setDescription(e.currentTarget.value);
                                }}
                            ></Form.Control>
                            <Form.Text id="descriptionHelp" muted>
                                2 or 3 adjectives separated by dashes, e.g. red-bead-gall.
                            </Form.Text>
                        </Col>
                    </Row>

                    <Row>
                        <Col>
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
                        </Col>
                    </Row>
                </Form>
                <Alert hidden={!errMessage} key="errAlert" variant="danger">
                    {errMessage}
                </Alert>
            </Modal.Body>
            <Modal.Footer>
                <Row className="d-flex justify-content-end">
                    <Col>
                        <Button variant="primary" disabled={!name || !genus || !family || !host} onClick={() => done(false)}>
                            Done
                        </Button>{' '}
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
            </Modal.Footer>
        </Modal>
    );
};

export default UndescribedFlow;
