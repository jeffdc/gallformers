use crate::gallformersdb::GallformersDB;
use crate::plantdb::PlantDB;
use crate::species::Species;
use crate::species::SpeciesName;
use crate::Res;
use rusqlite::Connection;
use std::collections::HashMap;
use std::path::PathBuf;

pub fn export() -> Res<()> {
    let mut gf_db_file = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    gf_db_file.pop();
    gf_db_file.push("prisma/gallformers.sqlite");
    let gf_c = Connection::open(gf_db_file.as_path())?;
    let mut gf_db = GallformersDB::new(&gf_c);

    let mut plant_db_file = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    plant_db_file.push("plants.db");
    let plant_c = Connection::open(plant_db_file.as_path())?;
    let mut plant_db = PlantDB::new(&plant_c);

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
        let sp_name = SpeciesName::new(sp.as_ref().unwrap().name.to_string());
        species_map.insert(sp_name, sp.unwrap().id);
    }

    gf_db.conn.execute_batch("BEGIN TRANSACTION;")?;

    // add all of the regions in the plants db as places and since they are all states assign them to the US
    let country_us = gf_db.select_place_by_name("United States")?.unwrap();
    let mut places = HashMap::new();
    for r in plant_db.select_all_regions()? {
        let id = gf_db.create_or_fetch_place(&r)?;
        gf_db.create_place_place(country_us.id, id)?;
        places.insert(r.name.clone(), id);
    }

    for s in species_map {
        let species_id = s.1;
        match plant_db.select_plant_regions(s.0.clone()) {
            Ok(regions) => {
                if regions.is_empty() {
                    println!("No match for: {:?}", s.0);
                }
                for region in regions {
                    match places.get(&region.name) {
                        Some(place_id) => gf_db.add_place_for_plant(species_id, *place_id)?,
                        None => println!("Failed to lookup place id for given region {:?}", region),
                    }
                }
            }
            _ => println!("No match for: {:?}", s.0),
        };
    }
    gf_db.conn.execute_batch("END TRANSACTION;")?;

    Ok(())
}
