import { useAuth0 } from '@auth0/auth0-react';
import React from 'react';
import LoginButton from './login';

const Auth = ({ children }: { children: JSX.Element }): JSX.Element => {
    const { isAuthenticated, isLoading } = useAuth0();

    if (!isAuthenticated) {
        return (
            <div className="m-3 p-3">
                <p>
                    These are not the droids you are looking for. If you think that you really do want some droids, then login
                    first.
                </p>
                <LoginButton />
            </div>
        );
    }

    if (isLoading) {
        return <p className="m-3 p-3">Hold tight. Working on vetting you...</p>;
    }

    return children;
};

export default Auth;
