/* eslint-disable @typescript-eslint/ban-ts-comment */
import { PrismaClient } from '@prisma/client';

/**
 * The one and only connection to the database.
 */

// Useful for logging SQL that is generated for debugging the search
// const db = new PrismaClient({ log: ['query'] });
// db.$on('query', (e) => {
//     console.log(e);
// });

// prisma connection management "fun" - basically in dev mode next ends up reloading this over and over again
// this leads to alll kinds of problems - https://github.com/prisma/prisma-client-js/issues/228#issuecomment-618433162
let db: PrismaClient;
if (process.env.NODE_ENV === 'production') {
    db = new PrismaClient();
    console.log('Production: Created DB connection.');
} else {
    // Ensure the prisma instance is re-used during hot-reloading
    // Otherwise, a new client will be created on every reload
    // @ts-ignore
    globalThis['db'] = globalThis['db'] || new PrismaClient();
    // globalThis['db'] = globalThis['db'] || new PrismaClient({ log: ['query'] });
    // @ts-ignore
    db = globalThis['db'];

    // db.$on('query', (e) => {
    //     console.log(e);
    // });
    // console.log('Development: Created DB connection.');
    // console.log(new Error().stack);
}

// const db = new PrismaClient();
Object.freeze(db);
// make sure foreign key support is turned on
db.$executeRaw('PRAGMA foreign_keys = ON');

export default db;
