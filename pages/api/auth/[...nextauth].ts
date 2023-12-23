import NextAuth from 'next-auth';
import Auth0Provider from 'next-auth/providers/auth0';

if (!process.env.AUTH0_CLIENT_ID || !process.env.AUTH0_SECRET || !process.env.AUTH0_DOMAIN || !process.env.SECRET) {
    const msg = 'The ENV is not configured properly for authentication to work.';
    console.error(msg);
    throw new Error(msg);
}

export default NextAuth.default({
    providers: [
        Auth0Provider.default({
            clientId: process.env.AUTH0_CLIENT_ID,
            clientSecret: process.env.AUTH0_SECRET,
            issuer: process.env.AUTH0_DOMAIN,
        }),
    ],
    session: {
        strategy: 'jwt',
    },
    jwt: {
        secret: process.env.SECRET,
    },
    events: {},
    debug: false,
});
