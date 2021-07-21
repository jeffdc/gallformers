use crate::plant::PlantCSV;
use crate::plant::PlantName;
use crate::plant::SpeciesType;
use crate::plantdb::AliasType;
use crate::plantdb::PlantDB;
use crate::Res;
use rusqlite::Connection;
use serde_json::Map;
use serde_json::Value;
use std::fs::File;
use std::io::Read;
use std::path::PathBuf;

pub fn import() -> Res<()> {
    let mut plant_db_file = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    plant_db_file.push("plants.db");
    let plant_c = Connection::open(plant_db_file.as_path())?;
    let mut plant_db = PlantDB::new(&plant_c);

    // load the schema into the new DB
    let mut sql_file = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    sql_file.push("plants.sql");
    match File::open(sql_file.as_path()) {
        Ok(mut file) => {
            let mut sql = String::new();
            file.read_to_string(&mut sql).unwrap();
            plant_db.conn.execute_batch(&sql)?;
        }
        Err(e) => {
            println!("Failed to open database schema {:?}. {}", sql_file, e);
        }
    }

    let mut region_json = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    region_json.push("regions.json");
    let parsed: Value = serde_json::from_str(&std::fs::read_to_string(region_json)?)?;
    let region_map: Map<String, Value> = parsed.as_object().unwrap().clone();
    let mut csv_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    csv_dir.push("data");

    plant_db.conn.execute_batch("BEGIN TRANSACTION;")?;
    for csv_file in csv_dir.read_dir()? {
        let csv = csv_file?.path();
        let file = File::open(&csv)?;
        let region_abbr = csv
            .file_stem()
            .ok_or("Missing Region")?
            .to_str()
            .ok_or("Invalid unicode in filename")?;
        let region_name = region_map
            .get(region_abbr)
            .ok_or("Unknown Region")?
            .as_str()
            .ok_or("Unknown Region")?;
        let region_id = plant_db.create_region(region_name, region_abbr)?;

        println!(
            "Processing {:?} with abbr {} and name {}.",
            csv.to_str(),
            region_abbr,
            region_name
        );
        let mut rdr = csv::Reader::from_reader(file);
        for r in rdr.deserialize() {
            let plant: PlantCSV = r?;
            let raw_name = plant.name.to_string();
            let name = PlantName::new(raw_name)?;
            if name.species_type == SpeciesType::OrthVar || name.species_type == SpeciesType::Other
            {
                // for now we are going to skip all of the weird taxonomy naming  variations and related
            } else {
                let id = plant_db.create_plant(&plant, name)?;
                if !plant.common_name.trim().is_empty() {
                    let cn_id = plant_db.create_alias(&plant.common_name)?;
                    plant_db.relate_alias_to_plant(
                        &cn_id.to_string(),
                        AliasType::Common,
                        &id.to_string(),
                    )?;
                }
                plant_db.create_plant_region(&id.to_string(), &region_id.to_string())?;
            }
        }
    }
    plant_db.conn.execute_batch("END TRANSACTION;")?;

    Ok(())
}
