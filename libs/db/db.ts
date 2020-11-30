import { PrismaClient } from '@prisma/client';

/**
 * The one and only connection to the database.
 */

// Useful for logging SQL that is generated for debugging the search
//const db = new PrismaClient({ log: ['query'] });
// db.$on('query', (e) => {
//     console.log(e);
// });

const db = new PrismaClient();
Object.freeze(db);
// make sure foreign key support is turned on
db.$executeRaw('PRAGMA foreign_keys = ON');

export default db;
