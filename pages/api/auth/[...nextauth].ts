import NextAuth from 'next-auth';
import Providers from 'next-auth/providers';
import { NextApiRequest, NextApiResponse } from 'next-auth/_utils';

if (!process.env.AUTH0_CLIENT_ID || !process.env.AUTH0_SECRET || !process.env.AUTH0_DOMAIN || !process.env.SECRET) {
    const msg = 'The ENV is not configured properly for authentication to work.';
    console.log(msg);
    throw new Error(msg);
}

const options = {
    providers: [
        Providers.Auth0({
            clientId: process.env.AUTH0_CLIENT_ID,
            clientSecret: process.env.AUTH0_SECRET,
            domain: process.env.AUTH0_DOMAIN,
        }),
    ],
    session: {
        jwt: true,
    },
    jwt: {
        secret: process.env.SECRET,
        encryption: true,
    },
    events: {},
    debug: true,

    // A database is optional, but required to persist accounts in a database
    // database: process.env.DATABASE_URL,
};

export default (req: NextApiRequest, res: NextApiResponse<unknown>): Promise<void> => NextAuth(req, res, options);
