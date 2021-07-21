use crate::gallformersdb::GallformersDB;
use crate::plantdb::PlantDB;
use crate::species::to_species_name;
use crate::species::Species;
use crate::Res;
use rusqlite::Connection;
use std::collections::HashMap;
use std::path::PathBuf;

pub fn export() -> Res<()> {
    let mut gf_db_file = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    gf_db_file.pop();
    gf_db_file.push("prisma/gallformers.sqlite");
    let gf_c = Connection::open(gf_db_file.as_path())?;
    let gf_db = GallformersDB::new(&gf_c);

    let mut plant_db_file = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    plant_db_file.push("plants.db");
    let plant_c = Connection::open(plant_db_file.as_path())?;
    let plant_db = PlantDB::new(&plant_c);

    let mut stmt = gf_db
        .conn
        .prepare("SELECT id, name from species WHERE taxoncode = 'plant';")?;
    let species = stmt.query_map([], |row| {
        Ok(Species {
            id: row.get(0)?,
            name: row.get(1)?,
        })
    })?;

    let mut species_map = HashMap::new();
    for sp in species {
        let sp_name = to_species_name(&sp.as_ref().unwrap().name);
        species_map.insert(sp_name, sp.unwrap().id);
    }

    let mut stmt_plants = plant_db.conn.prepare("SELECT id, name FROM plant;")?;
    let plants = stmt_plants.query_map([], |row| {
        Ok(Species {
            id: row.get(0)?,
            name: row.get(1)?,
        })
    })?;

    // generate a delta list of what matches and what does not
    for p in plants {
        println!("{:?}", p);
        // let name = p?.name;
        // let p_name = PlantName::new(&name);
        // let s_name = plant_name_to_species_name(&p_name?);
        // if species_map.contains_key(&s_name) {
        //     // exact match
        //     println!("{:?}", s_name);
        // } else {
        //     // no match
        // }
    }
    // gf_db.conn.execute_batch("BEGIN TRANSACTION;")?;
    // actual work
    // gf_db.conn.execute_batch("END TRANSACTION;")?;

    Ok(())
}
