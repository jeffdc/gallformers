/**
 * This program is used to execute the database migrations.
 * It should be run from the build target `migrate`:
 * e.g., `yarn migrate`
 */

try {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const Database = require('better-sqlite3-helper');
    const dbPath = `${process.cwd()}/prisma/gallformers.sqlite`;

    const config = {
        path: dbPath,
        readonly: false,
        fileMustExist: true,
        WAL: false,
        verbose: true,
        migrate: {
            force: true,
            table: 'migration',
            migrationPath: './migrations',
        },
    };

    // hack to force flush migrations. :(
    const hack = new Database(config);
    hack.run('VACUUM;');
    hack.close();
    const DB = new Database(config);
    console.log(`Initing DB ${JSON.stringify(DB, null, '  ')}`);
    DB.close();
} catch (e) {
    console.error(e);
}
