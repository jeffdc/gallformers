use serde_json::Value;
use serde_json::Map;
use std::path::PathBuf;
use rusqlite::Statement;
use rusqlite::{ Connection, Error };
use std::fs::File;
use serde_derive::Deserialize;

#[derive(Debug,Deserialize)]
pub struct Plant {
    // "Symbol","Synonym Symbol","Scientific Name with Author","State Common Name","Family"
    #[serde(rename = "Symbol")]
    symbol: String,
    #[serde(rename = "Synonym Symbol")]
    syn_symbol: String,
    #[serde(rename = "Scientific Name with Author")]
    name: String,
    #[serde(rename = "State Common Name")]
    common_name: String,
    #[serde(rename = "Family")]
    family: String,
}

pub struct DBContext<'a> {
    pub conn: &'a Connection,
    pub create_plant_statement: Option<Statement<'a>>,
    pub create_common_name_statement: Option<Statement<'a>>,
    pub create_plant_region_statement: Option<Statement<'a>>,
    pub create_region_statement: Option<Statement<'a>>,
    pub select_plantid_statement: Option<Statement<'a>>,
    pub relate_commonname_to_plant_statement: Option<Statement<'a>>,
    pub select_commonnameid_statement: Option<Statement<'a>>,
}

impl <'a> DBContext<'a> {
    pub fn new(conn: &'a Connection) -> Self {
        return DBContext {
            conn,
            create_plant_statement: None,
            create_common_name_statement: None,
            create_plant_region_statement: None,
            create_region_statement: None,
            select_plantid_statement: None,
            relate_commonname_to_plant_statement: None,
            select_commonnameid_statement: None,
        };
    }

    pub fn select_plantid(&mut self, name: &str) -> Result<i64, Error> {
        if let None = &self.select_plantid_statement {
            let stmt = self.conn.prepare("SELECT id FROM plant WHERE name = :name;")?;
            self.select_plantid_statement = Some(stmt);
        };
        let mut rows = self.select_plantid_statement.as_mut().unwrap().query(&[(":name", &name)])?;
        let row = rows.next()?;
        let id = row.map(|r| r.get(0).expect("Failed to fetch plant id.")).expect("Failed to fetch plant id.");
        return Ok(id);
    }

    pub fn select_commonnameid(&mut self, name: &str) -> Result<i64, Error> {
        if let None = &self.select_commonnameid_statement {
            let stmt = self.conn.prepare("SELECT id FROM commonname WHERE name = :name;")?;
            self.select_commonnameid_statement = Some(stmt);
        };
        let mut rows = self.select_commonnameid_statement.as_mut().unwrap().query(&[(":name", &name)])?;
        let row = rows.next()?;
        let id = row.map(|r| r.get(0).expect("Failed to fetch commonname id.")).expect("Failed to fetch commonname id.");
        return Ok(id);
    }

    pub fn create_plant(&mut self, plant: &Plant) -> Result<i64, Error> {
        if let None = &self.create_plant_statement {
            let stmt = self.conn.prepare("INSERT OR IGNORE INTO plant (name, symbol, symbolsynonym, family) VALUES (:name, :symbol, :symbolsynonym, :family)")?;
            self.create_plant_statement = Some(stmt);
        };
        // println!("Creating plant {:?}", plant);
        self.create_plant_statement.as_mut().unwrap().execute(&[(":name", &plant.name), (":symbol", &plant.symbol), (":symbolsynonym", &plant.syn_symbol), (":family", &plant.family)])?;

        return self.select_plantid(&plant.name);
    }

    pub fn create_common_name(&mut self, name: &str) -> Result<i64, Error> {
        if let None = &self.create_common_name_statement {
            let stmt = self.conn.prepare("INSERT OR IGNORE INTO commonname (name) VALUES (:name)")?;
            self.create_common_name_statement = Some(stmt);
        };
        // println!("Creating commonname {}", name);
        self.create_common_name_statement.as_mut().unwrap().execute(&[(":name", &name)])?;

        return self.select_commonnameid(&name);
    }

    pub fn relate_commonname_to_plant(&mut self, cn_id: &str, plant_id: &str) -> Result<(), Error> {
        if let None = &self.relate_commonname_to_plant_statement {
            let stmt = self.conn.prepare("INSERT INTO plantcommonname (plant_id, commonname_id) VALUES (:plant_id, :commonname_id)")?;
            self.relate_commonname_to_plant_statement = Some(stmt);
        };
        // println!("Relating plant {} to commonname {}", plant_id, cn_id);
        self.relate_commonname_to_plant_statement.as_mut().unwrap().execute(&[(":plant_id", &plant_id), (":commonname_id", &cn_id)])?;

        return Ok(());
    }

    pub fn create_plant_region(&mut self, plant_id: &str, region_id: &str) -> Result<i64, Error> {
        if let None = &self.create_plant_region_statement {
            let stmt = self.conn.prepare("INSERT INTO plantregion (plant_id, region_id) VALUES (:plant_id, :region_id)")?;
            self.create_plant_region_statement = Some(stmt);
        };
        // println!("Creating plant region rel plant {} region {}", plant_id, region_id);
        self.create_plant_region_statement.as_mut().unwrap().execute(&[(":plant_id", &plant_id), (":region_id", &region_id)])?;

        return Ok(self.conn.last_insert_rowid());
    }

    pub fn create_region(&mut self, name: &str, code: &str) -> Result<i64, Error> {
        if let None = &self.create_region_statement {
            let stmt = self.conn.prepare("INSERT INTO region (name, code) VALUES (:name, :code)")?;
            self.create_region_statement = Some(stmt);
        };
        // println!("Creating region {} - {}", name, code);
        self.create_region_statement.as_mut().unwrap().execute(&[(":name", &name), (":code", &code)])?;

        return Ok(self.conn.last_insert_rowid());
    }
}

type Err = Box<dyn std::error::Error>;
type Res<T> = Result<T, Err>;

fn import() -> Res<()> {
    let mut db_file = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    db_file.pop();
    db_file.push("prisma/plants.db");
    let conn = Connection::open(db_file.as_path())?;
    let mut ctx = DBContext::new(&conn);

    let mut region_json = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    region_json.push("data/regions.json");
    let parsed: Value = serde_json::from_str(&std::fs::read_to_string(region_json)?)?;
    let region_map: Map<String, Value> = parsed.as_object().unwrap().clone();
    
    let mut csv_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    csv_dir.push("data/20210708");

    ctx.conn.execute_batch("BEGIN TRANSACTION;")?;
    for csv_file in csv_dir.read_dir()? {
        let csv = csv_file?.path();
        let file = File::open(&csv)?;
        let region_abbr = csv.file_stem().ok_or_else(|| "Missing Region")?.to_str().ok_or_else(|| "Invalid unicode in filename")?;
        let region_name = region_map.get(region_abbr).ok_or_else(|| "Unknown Region")?.as_str().ok_or_else(|| "Unknown Region")?;
        let region_id = ctx.create_region(region_name, region_abbr)?;

        println!("Processing {:?} with abbr {} and name {}.", csv.to_str(), region_abbr, region_name);
        let mut rdr = csv::Reader::from_reader(file);
        for r in rdr.deserialize() {
            let plant: Plant = r?;
    
            let id = ctx.create_plant(&plant)?;
            if !plant.common_name.trim().is_empty() {
                let cn_id = ctx.create_common_name(&plant.common_name)?;
                ctx.relate_commonname_to_plant(&cn_id.to_string(), &id.to_string())?;
            }
            ctx.create_plant_region(&id.to_string(), &region_id.to_string())?;
        }    
    }
    ctx.conn.execute_batch("END TRANSACTION;")?;

    return Ok(());
}

fn main() -> Res<()> {
    match import() {
        Ok(()) => return Ok(()),
        Err(err) => {
            println!("{}", err);
            return Err(err);
        }
    }
}
