import * as React from 'react';
import { Button, Col, Modal, Row } from 'react-bootstrap';

export type ConfirmationOptions = {
    catchOnCancel?: boolean;
    variant: 'danger' | 'info';
    title: string;
    message: string;
};

export const EmptyOptions: ConfirmationOptions = {
    variant: 'info',
    title: '',
    message: '',
};

type ConfirmationDialogProps = ConfirmationOptions & {
    show: boolean;
    onSubmit: () => void;
    onClose: () => void;
};

export const ConfirmationDialog: React.FC<ConfirmationDialogProps> = ({ show, title, variant, message, onSubmit, onClose }) => {
    return (
        <Modal show={show}>
            <Modal.Header id="alert-dialog-title">
                <Modal.Title>{title}</Modal.Title>
            </Modal.Header>
            <Modal.Body>{message}</Modal.Body>
            <Modal.Footer>
                <div className="d-flex justify-content-end">
                    {variant === 'danger' && (
                        <Row>
                            <Col xs={4}>
                                <Button variant="primary" onClick={onSubmit}>
                                    Yes
                                </Button>
                            </Col>
                            <Col xs={4}>
                                <Button variant="secondary" onClick={onClose} autoFocus>
                                    CANCEL
                                </Button>
                            </Col>
                        </Row>
                    )}

                    {variant === 'info' && (
                        <Button color="primary" onClick={onSubmit}>
                            OK
                        </Button>
                    )}
                </div>
            </Modal.Footer>
        </Modal>
    );
};
