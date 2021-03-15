import React, { useState } from 'react';
import { Button, Modal } from 'react-bootstrap';
import toast, { Toaster } from 'react-hot-toast';
import { capitalizeFirstLetter } from '../libs/utils/util';

type Props = {
    type: string;
    keyField: string;
    defaultValue: string | undefined;
    showModal: boolean;
    setShowModal: (showModal: boolean) => void;
    setNewValue: (newValue: string) => void;
};

const EditName = ({ type, keyField, defaultValue, showModal, setShowModal, setNewValue }: Props): JSX.Element => {
    const [value, setValue] = useState(defaultValue);

    return (
        <>
            <div>
                <Toaster />
            </div>
            <Modal show={showModal} onHide={() => setShowModal(false)} size="lg">
                <Modal.Header closeButton>
                    <Modal.Title>{`Edit ${type} ${capitalizeFirstLetter(keyField)}`}</Modal.Title>
                </Modal.Header>
                <Modal.Body>
                    <input
                        className="form-control"
                        type="text"
                        defaultValue={defaultValue}
                        onChange={(e) => setValue(e.currentTarget.value)}
                    />
                </Modal.Body>
                <Modal.Footer>
                    <Button variant="secondary" onClick={() => setShowModal(false)}>
                        Cancel
                    </Button>
                    <Button
                        variant="primary"
                        type="submit"
                        onClick={() => {
                            if (value == undefined || value === '') {
                                toast.error(`The name must not be empty.`);
                                return;
                            }
                            setNewValue(value);
                            setShowModal(false);
                        }}
                    >
                        Save Changes
                    </Button>
                </Modal.Footer>
            </Modal>
        </>
    );
};

export default EditName;
