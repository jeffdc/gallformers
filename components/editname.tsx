import React, { useState } from 'react';
import { Button, Modal } from 'react-bootstrap';
import toast, { Toaster } from 'react-hot-toast';
import { capitalizeFirstLetter } from '../libs/utils/util';

export type RenameEvent = {
    old: string | undefined;
    new: string;
    addAlias: boolean;
};

type Props = {
    type: string;
    keyField: string;
    defaultValue: string | undefined;
    showModal: boolean;
    setShowModal: (showModal: boolean) => void;
    renameCallback: (e: RenameEvent) => void;
};

const EditName = ({ type, keyField, defaultValue, showModal, setShowModal, renameCallback }: Props): JSX.Element => {
    const [value, setValue] = useState(defaultValue);
    const [addAlias, setAddAlias] = useState(false);

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
                    {(type === 'Gall' || type === 'Host') && (
                        <>
                            <br />
                            <input type="checkbox" onChange={(e) => setAddAlias(e.currentTarget.checked)} /> Add Alias for old
                            name?
                            <div className="mt-2 small">
                                If you want to reassign the species to a different genus simply enter the new name (full couplet)
                                with the new genus name. If the genus does not yet exist it will be created and assigned to the
                                same family. If already exists the species will be re-assigned to the genus. You have be be
                                careful and make sure that you type the genus name exactly as it is if it already exists,
                                otherwise a new genus with the differing name will be created.
                            </div>
                        </>
                    )}
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
                            } else {
                                renameCallback({
                                    old: defaultValue,
                                    new: value,
                                    addAlias: addAlias,
                                });
                                setShowModal(false);
                            }
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
