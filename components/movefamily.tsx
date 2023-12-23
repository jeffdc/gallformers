import React, { useState } from 'react';
import { Button, Modal } from 'react-bootstrap';
import { Typeahead } from 'react-bootstrap-typeahead';
import toast, { Toaster } from 'react-hot-toast';
import { FamilyAPI, Genus } from '../libs/api/apitypes.js';

type TaxFamily = Omit<FamilyAPI, 'parent'>;
export type MoveEvent = {
    new: TaxFamily;
};

type Props = {
    genera: Genus[];
    families: TaxFamily[];
    showModal: boolean;
    setShowModal: (showModal: boolean) => void;
    moveCallback: (e: MoveEvent) => void;
};

const MoveFamily = ({ genera, families, showModal, setShowModal, moveCallback }: Props): JSX.Element => {
    const [value, setValue] = useState<TaxFamily>();

    return (
        <>
            <div>
                <Toaster />
            </div>
            <Modal show={showModal} onHide={() => setShowModal(false)} size="lg">
                <Modal.Header closeButton>
                    <Modal.Title>
                        {`Moving ${genera.length > 1 ? 'Genera' : 'Genus'}: ${genera.map((g) => g.name).join(', ')}`}
                    </Modal.Title>
                </Modal.Header>
                <Modal.Body>
                    <Typeahead
                        id="family"
                        placeholder="Family"
                        options={families}
                        labelKey="name"
                        selected={value ? [value] : []}
                        onChange={(g) => {
                            // TODO hopefully Option in the control will be parameterized in the future
                            setValue(g[0] as TaxFamily);
                        }}
                        clearButton
                    />
                    <div className="mt-2 text-danger small">
                        Once you select a new Family and press the &lsquo;Move to Selected Family&rsquo; button the change will be
                        made in the database and the data saved.
                    </div>
                </Modal.Body>
                <Modal.Footer>
                    <Button variant="secondary" onClick={() => setShowModal(false)}>
                        Cancel
                    </Button>
                    <Button
                        variant="primary"
                        type="submit"
                        disabled={!value}
                        onClick={() => {
                            if (!value) {
                                toast.toast.error(`You must select a new family, or cancel if you do not want to make changes.`);
                            } else {
                                moveCallback({
                                    new: value,
                                });
                                setShowModal(false);
                            }
                        }}
                    >
                        Move To Selected Family
                    </Button>
                </Modal.Footer>
            </Modal>
        </>
    );
};

export default MoveFamily;
