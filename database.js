
const Database = require('better-sqlite3-helper');
// future self (or others) must use process.cwd() here as Vercel deploys to a diff dir
// https://nextjs.org/docs/basic-features/data-fetching#reading-files-use-processcwd
const dbPath = `${process.cwd()}/prisma/gallformers.sqlite`;
// console.log(`Trying to open the database at "${dbPath}"`);

const config = {
  path: dbPath,
  readonly: false,
  fileMustExist: false,
  migrate: true,
  WAL: false,
  migrate: {
    force: true,
    table: 'migration',
    migrationPath: './migrations'
  }
};

// hack to force flush migrations. :(
const hack = new Database(config);
hack.close();
export const DB = new Database(config);
// console.log(`The DB is ${JSON.stringify(DB, null, '  ')}`);

// const tables = DB.query("SELECT * from sqlite_master WHERE type='table'");
// console.log(`DB tables: ${JSON.stringify(tables.map(t => t.name), null, '  ')}`);

// local helpers
function allIfNull(x) {
  return !x ? '%' : x
}

// these are the exported backend API. this is a mess and we will need to break this up I am thinking.
export async function getFamilies() {
  const sql =
      `SELECT *
      FROM family
      ORDER BY name ASC`;
  const families = DB.prepare(sql).all();
 
  return families    
}

export async function getFamily(id) {
  return DB.prepare('SELECT * from family WHERE family_id = ?').get(id);
}

export async function getLocations() {
  return newdb.location.findMany({});
  // const locs = DB.prepare('SELECT * from location ORDER BY loc ASC').all();
  // return locs;
}

export async function getAlignments() {
  const data = DB.prepare('SELECT * from alignment ORDER BY alignment ASC').all();
  return data;
}

export async function getCells() {
  const data = DB.prepare('SELECT * from cells ORDER BY cells ASC').all();
  return data;
}

export async function getColors() {
  const data = DB.prepare('SELECT * from color ORDER BY color ASC').all();
  return data;
}

export async function getShapes() {
  const data = DB.prepare('SELECT * from shape ORDER BY shape ASC').all();
  return data;
}

export async function getTextures() {
  const data = DB.prepare('SELECT * from texture ORDER BY texture ASC').all();
  return data;
}

export async function getWalls() {
  const data = DB.prepare('SELECT * from walls ORDER BY walls ASC').all();
  return data;
}

export async function getSpecies() {
  const sql =
      `SELECT *
      FROM species;`
  
  const species = DB.prepare(sql).all();
  return species;
}

export async function getSpeciesById(id) {
  return DB.prepare('SELECT * from species WHERE species_id = ?').get(id);
}

export async function getGalls() {
  const sql =
      `SELECT v_gall.*
      FROM v_gall
      ORDER BY name ASC`;
  
  const galls = DB.prepare(sql).all();
  return galls
}

export async function getGall(id) {
  let sql = 
    `SELECT *
    FROM v_gall
    WHERE species_id = ?`;

    const gall = DB.prepare(sql).get(id);
    return gall
}

export async function getHostsByGall(id) {
  const sql = 
    `SELECT DISTINCT hostsp.species_id, hostsp.name, hostsp.synonyms, hostsp.commonnames
    FROM host 
    INNER JOIN species as hostsp ON (host.host_species_id = hostsp.species_id) 
    INNER JOIN species ON (host.species_id = species.species_id)
    WHERE host.species_id = ?`

  const hosts = DB.prepare(sql).all(id);
  return hosts;
}

export async function getSourcesByGall(id) {
  const sql = `
    SELECT DISTINCT * 
    FROM speciessource 
    INNER JOIN source ON (speciessource.source_id = source.source_id)
    WHERE species_id = ?`

  const sources = DB.prepare(sql).all(id);

  return sources;
}

export async function getGallFamilies() {
  const sql =
        `SELECT DISTINCT family.*
        FROM gall
            INNER JOIN
            species ON (gall.species_id = species.species_id) 
            INNER JOIN
            family ON (species.family_id = family.family_id)      
        ORDER BY family.name ASC`;
    const families = DB.prepare(sql).all();
    return families;
}

export async function getGallsByHost(id) {
  const sql = 
    `SELECT DISTINCT species.species_id, species.name, species.synonyms, species.commonnames
    FROM host 
    INNER JOIN species as hostsp ON (host.host_species_id = hostsp.species_id) 
    INNER JOIN species ON (host.species_id = species.species_id)
    WHERE host.host_species_id = ?`;

  const galls = DB.prepare(sql).all(id);
  return galls;  
}

export async function getHost(id) {
  const sql = 
        `SELECT DISTINCT species.* 
        FROM host 
        INNER JOIN species ON (species.species_id = host.host_species_id)
        WHERE species.species_id = ?`;
    const host = DB.prepare(sql).get(id);
    return host;
}

export async function getHosts() {
  return newdb.host.findMany({
    include: {
      hostspecies: {}
    }
  });
  // const sql =
  //   `SELECT DISTINCT species.*
  //   FROM host 
  //   INNER JOIN species ON (host.host_species_id = species.species_id)
  //   ORDER BY species.name ASC`;
  // const hosts = DB.prepare(sql).all();
  // return hosts;
}

export async function getSource(id) {
  const source = DB.prepare('SELECT * from source WHERE id = ?').all(d);
  return source;
}

export async function search(q) {
  const sql = 
    `SELECT DISTINCT v_gall.*, hostsp.name as host_name, hostsp.species_id AS host_species_id
    FROM v_gall
    INNER JOIN host ON (v_gall.species_id = host.species_id)
    INNER JOIN species AS hostsp ON (hostsp.species_id = host.host_species_id)
    WHERE (detachable = ? OR detachable is NOT NULL) AND 
        (texture LIKE ? OR texture IS NULL) AND 
        (alignment LIKE ? OR alignment IS NULL) AND 
        (walls LIKE ? OR walls IS NULL) AND 
        hostsp.name LIKE ? AND 
        (loc LIKE ? OR loc IS NULL)
    ORDER BY v_gall.name ASC`;

    const stmt = DB.prepare(sql);
    const detachable = allIfNull(q.detachable) === 'no' ? 0 : 1;
    const galls = stmt.all(detachable, allIfNull(q.texture), allIfNull(q.alignment), allIfNull(q.walls), 
             allIfNull(q.host), allIfNull(q.location));
           
    return galls;
}