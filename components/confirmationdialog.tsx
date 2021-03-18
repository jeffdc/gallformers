import * as React from 'react';
import { Alert, Button } from 'react-bootstrap';

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
        <Alert show={show}>
            <Alert.Heading id="alert-dialog-title">{title}</Alert.Heading>
            {message}
            <div className="d-flex justify-content-end">
                {variant === 'danger' && (
                    <>
                        <Button color="primary" onClick={onSubmit}>
                            Yes
                        </Button>
                        <Button color="primary" onClick={onClose} autoFocus>
                            CANCEL
                        </Button>
                    </>
                )}

                {variant === 'info' && (
                    <Button color="primary" onClick={onSubmit}>
                        OK
                    </Button>
                )}
            </div>
        </Alert>
    );
};
