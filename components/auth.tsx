import { signIn, useSession } from 'next-auth/client';
import React from 'react';

const Auth = ({ children }: { children: JSX.Element }): JSX.Element => {
    const [session, loading] = useSession();

    if (!session) {
        return (
            <div className="m-3 p-3">
                <p>
                    These are not the droids you are looking for. If you think that you really do want some droids, then login
                    first.
                </p>
                {/* eslint-disable-next-line @typescript-eslint/no-explicit-any */}
                <button onClick={signIn as any}>Log In</button>
            </div>
        );
    }

    if (loading) {
        return <p className="m-3 p-3">Hold tight. Working on vetting you...</p>;
    }

    return children;
};

export default Auth;
