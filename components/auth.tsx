import { signIn, useSession } from 'next-auth/react';
import React from 'react';

export const superAdmins = ['jeff', 'adamjameskranz'];

const Auth = ({ superAdmin, children }: { superAdmin?: boolean; children: JSX.Element }): JSX.Element => {
    const { data: session, status } = useSession();

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

    if (!!superAdmin && session.user && session.user.name && !superAdmins.includes(session.user.name)) {
        return (
            <div className="m-3 p-3">
                <p>Hmmm. You should probably not be here.</p>
            </div>
        );
    }

    if (status === 'loading') {
        return <p className="m-3 p-3">Hold tight. Working on vetting you...</p>;
    }

    return children;
};

export default Auth;
