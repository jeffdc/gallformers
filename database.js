
const Database = require('better-sqlite3-helper');
export const DB = new Database({
  path: './gallformers.sqlite',
  readonly: false,
  fileMustExist: false,
  WAL: true,
  migrate: {
    force: true,
    table: 'migration',
    migrationPath: './migrations'
  }
})