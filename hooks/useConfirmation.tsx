import { createContext, ReactNode, useContext, useRef, useState, useEffect } from 'react';
import { ConfirmationDialog, ConfirmationOptions, EmptyOptions } from '../components/confirmationdialog';

const ConfirmationServiceContext = createContext<(options: ConfirmationOptions) => Promise<void>>(() =>
    Promise.reject(new Error('Confirmation service not available')),
);

export const useConfirmation = (): ((options: ConfirmationOptions) => Promise<void>) => {
    const context = useContext(ConfirmationServiceContext);
    if (typeof window === 'undefined') {
        // Return a no-op function during SSR
        return () => Promise.resolve();
    }
    return context;
};

type Props = {
    children: ReactNode;
};

export const ConfirmationServiceProvider = ({ children }: Props): JSX.Element => {
    const [mounted, setMounted] = useState(false);
    const [confirmationState, setConfirmationState] = useState<ConfirmationOptions>(EmptyOptions);
    const awaitingPromiseRef = useRef<{
        resolve: () => void;
        reject: () => void;
    }>();

    useEffect(() => {
        setMounted(true);
    }, []);

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
        return mounted && confirmationState !== EmptyOptions;
    };

    return (
        <>
            {mounted && (
                <ConfirmationDialog show={shouldShow()} onSubmit={handleSubmit} onClose={handleClose} {...confirmationState} />
            )}
            <ConfirmationServiceContext.Provider value={openConfirmation}>{children}</ConfirmationServiceContext.Provider>
        </>
    );
};
