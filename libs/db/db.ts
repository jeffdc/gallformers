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
    // @ts-ignore
    if (!global.db) {
        // @ts-ignore
        global.db = new PrismaClient();
        console.log('Development: Created DB connection.');
    }

    // @ts-ignore
    db = global.db;
}

// const db = new PrismaClient();
Object.freeze(db);
// make sure foreign key support is turned on
db.$executeRaw('PRAGMA foreign_keys = ON');

export default db;
