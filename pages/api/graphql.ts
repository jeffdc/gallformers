import { ApolloServer, gql } from 'apollo-server-micro';
import { schema } from '../../graphql/schema';
import { context } from '../../graphql/context';
import { NextApiRequest, NextApiResponse } from 'next';
import { ApolloServerPluginLandingPageGraphQLPlayground } from 'apollo-server-core';

// const typeDefs = gql`
//     type Glossary {
//         id: ID
//     }

//     type Query {
//         glossary: Glossary
//     }
// `;

// const resolvers = {
//     Query: {
//         glossary: () => {
//             return {
//                 id: 'Foo',
//             };
//         },
//     },
// };

const apolloServer = new ApolloServer({
    schema,
    context,
    plugins: [ApolloServerPluginLandingPageGraphQLPlayground()],
});

const startServer = apolloServer.start();

export default async function handler(req: NextApiRequest, res: NextApiResponse): Promise<void> {
    await startServer;
    await apolloServer.createHandler({
        path: '/api/graphql',
    })(req, res);
}

export const config = {
    api: {
        bodyParser: false,
    },
};
