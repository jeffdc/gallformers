import { PrismaClient } from '@prisma/client';

/**
 * The one and only connection to the database.
 */

// Useful for logging SQL that is generated for debugging the search
// const db = new PrismaClient({ log: ['query'] });
// db.$on('query', (e) => {
//     e.timestamp;
//     e.query;
//     e.params;
//     e.duration;
//     e.target;
//     console.log(e);
// });

const db = new PrismaClient();
Object.freeze(db);

export default db;
