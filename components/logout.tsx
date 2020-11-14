import { useAuth0 } from '@auth0/auth0-react';
import React from 'react';

const LogoutButton = (): JSX.Element => {
    const { logout } = useAuth0();
    const origin = `${process.env.APP_URL}`;

    return (
        <button className="btn-link btn-outline-light btn-sm" onClick={() => logout({ returnTo: origin })}>
            Log Out
        </button>
    );
};

export default LogoutButton;
