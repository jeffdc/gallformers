import sqlite3 from 'sqlite3'
import { open } from 'sqlite'

export async function database() {
  const database = await open({
    filename: './gallformers.sqlite',
    driver: sqlite3.Database
  });
  
  await database.migrate( { force: true } );

  return database;
}