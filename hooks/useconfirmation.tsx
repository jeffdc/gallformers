import { createContext, ReactNode, useContext, useRef, useState } from 'react';
import { ConfirmationDialog, ConfirmationOptions, EmptyOptions } from '../components/confirmationdialog';

const ConfirmationServiceContext = createContext<(options: ConfirmationOptions) => Promise<void>>(() => Promise.reject());

export const useConfirmation = (): ((options: ConfirmationOptions) => Promise<void>) => useContext(ConfirmationServiceContext);

type Props = {
    children: ReactNode;
};

export const ConfirmationServiceProvider = ({ children }: Props): JSX.Element => {
    const [confirmationState, setConfirmationState] = useState<ConfirmationOptions>(EmptyOptions);

    const awaitingPromiseRef = useRef<{
        resolve: () => void;
        reject: () => void;
    }>();

    const openConfirmation = (options: ConfirmationOptions) => {
        setConfirmationState(options);
        return new Promise<void>((resolve, reject) => {
            awaitingPromiseRef.current = { resolve, reject };
        });
    };

    const handleClose = () => {
        if (confirmationState?.catchOnCancel && awaitingPromiseRef.current) {
            awaitingPromiseRef.current.reject();
        }

        setConfirmationState(EmptyOptions);
    };

    const handleSubmit = () => {
        if (awaitingPromiseRef.current) {
            awaitingPromiseRef.current.resolve();
        }

        setConfirmationState(EmptyOptions);
    };

    const shouldShow = (): boolean => {
        return confirmationState !== EmptyOptions;
    };

    return (
        <>
            <ConfirmationDialog show={shouldShow()} onSubmit={handleSubmit} onClose={handleClose} {...confirmationState} />
            <ConfirmationServiceContext.Provider value={openConfirmation}>{children}</ConfirmationServiceContext.Provider>
        </>
    );
};
