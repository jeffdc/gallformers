import NextAuth from 'next-auth';
import Providers from 'next-auth/providers';

if (!process.env.AUTH0_CLIENT_ID || !process.env.AUTH0_SECRET || !process.env.AUTH0_DOMAIN || !process.env.SECRET) {
    const msg = 'The ENV is not configured properly for authentication to work.';
    console.error(msg);
    throw new Error(msg);
}

export default NextAuth({
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
});
