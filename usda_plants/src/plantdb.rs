use crate::plant::PlantCSV;
use crate::plant::PlantName;
use rusqlite::{Connection, Error, Statement};
use strum_macros::Display;

// fn row_to_plant(row: &Row) -> Result<Plant, Error> {
//     Ok(Plant {
//         id: row.get(0)?,
//         name: row.get(1)?,
//         symbol: row.get(2)?,
//         symbol_syn: row.get(3)?,
//         family: row.get(4)?,
//     })
// }

#[derive(Display, Debug)]
pub enum AliasType {
    #[strum(serialize = "common")]
    Common,
    #[strum(serialize = "orth. var.")]
    OrthVar,
    #[strum(serialize = "scientific")]
    Scientific,
}

/// simple context struct to manage the DB connection and prepared statements
pub struct PlantDB<'a> {
    pub conn: &'a Connection,
    create_plant_statement: Option<Statement<'a>>,
    create_alias_statement: Option<Statement<'a>>,
    create_plant_region_statement: Option<Statement<'a>>,
    create_region_statement: Option<Statement<'a>>,
    select_plantid_statement: Option<Statement<'a>>,
    relate_alias_to_plant_statement: Option<Statement<'a>>,
    select_aliasid_statement: Option<Statement<'a>>,
    plant_exists_statement: Option<Statement<'a>>,
    // select_all_plants_statement: Option<Statement<'a>>,
}

impl<'a> PlantDB<'a> {
    pub fn new(conn: &'a Connection) -> Self {
        PlantDB {
            conn,
            create_plant_statement: None,
            create_alias_statement: None,
            create_plant_region_statement: None,
            create_region_statement: None,
            select_plantid_statement: None,
            relate_alias_to_plant_statement: None,
            select_aliasid_statement: None,
            plant_exists_statement: None,
            // select_all_plants_statement: None,
        }
    }

    pub fn plant_exists(&mut self, name: &str) -> Result<bool, Error> {
        if self.plant_exists_statement.is_none() {
            let stmt = self
                .conn
                .prepare("SELECT id FROM plant WHERE name LIKE :name;")?;
            self.plant_exists_statement = Some(stmt);
        };
        let like_name = name.to_owned() + "%";
        let mut rows = self
            .plant_exists_statement
            .as_mut()
            .unwrap()
            .query(&[(":name", &like_name)])?;
        let row = rows.next()?;
        Ok(row.is_some())
    }

    /// fetches all Plants and returns a lazy iter of Plants
    // pub fn select_all_plants(&mut self) -> Result<AndThenRows<impl Fn(&Row) -> Result<Plant, Error>>, Error> {
    //     if let None = &self.select_all_plants_statement {
    //         let stmt = self.conn.prepare("SELECT id, name, symbol, symbolsynonym, family FROM plant;")?;
    //         self.select_all_plants_statement = Some(stmt);
    //     };
    //     let iter = self.select_all_plants_statement.as_mut().unwrap().query_and_then([], row_to_plant)?;
    //     return Ok(iter);
    // }

    /// fetches an ID for a Plant by name
    pub fn select_plantid(&mut self, name: &str) -> Result<i64, Error> {
        if self.select_plantid_statement.is_none() {
            let stmt = self
                .conn
                .prepare("SELECT id FROM plant WHERE name = :name;")?;
            self.select_plantid_statement = Some(stmt);
        };
        let mut rows = self
            .select_plantid_statement
            .as_mut()
            .unwrap()
            .query(&[(":name", &name)])?;
        let row = rows.next()?;
        let id = row
            .map(|r| r.get(0).expect("Failed to fetch plant id."))
            .expect("Failed to fetch plant id.");
        Ok(id)
    }

    /// fetches an ID for a aliasname by name
    pub fn select_alias_statement(&mut self, name: &str) -> Result<i64, Error> {
        if self.select_aliasid_statement.is_none() {
            let stmt = self
                .conn
                .prepare("SELECT id FROM aliasname WHERE name = :name;")?;
            self.select_aliasid_statement = Some(stmt);
        };
        let mut rows = self
            .select_aliasid_statement
            .as_mut()
            .unwrap()
            .query(&[(":name", &name)])?;
        let row = rows.next()?;
        let id = row
            .map(|r| r.get(0).expect("Failed to fetch aliasname id."))
            .expect("Failed to fetch aliasname id.");
        Ok(id)
    }

    /// inserts a plant, if it does not already exist. uniqueness is determined by name. returns the id of the plant.
    pub fn create_plant(&mut self, plant: &PlantCSV, name: PlantName) -> Result<i64, Error> {
        if self.create_plant_statement.is_none() {
            let stmt = self.conn.prepare("INSERT OR IGNORE INTO plant (rawname, symbol, symbolsynonym, family, genus, type, sspvar, hybridpair, author, secondauthor) VALUES (:rawname, :symbol, :symbolsynonym, :family, :genus, :type, :sspvar, :hybridpair, :author, :secondauthor)")?;
            self.create_plant_statement = Some(stmt);
        };
        // println!("Creating plant {:?}", plant);
        self.create_plant_statement.as_mut().unwrap().execute(&[
            (":rawname", &plant.name),
            (":symbol", &plant.symbol),
            (":symbolsynonym", &plant.syn_symbol),
            (":family", &plant.family),
            (":genus", &name.genus),
            (":type", &name.species_type.to_string()),
            (":sspvar", &name.sspvar.unwrap_or_else(|| "".to_string())),
            (
                ":hybridpair",
                &name
                    .hybrid
                    .map(|(a, b)| format!("{},{}", a, b))
                    .unwrap_or_else(|| "".to_string()),
            ),
            (":author", &name.author.unwrap_or_else(|| "".to_string())),
            (
                ":secondauthor",
                &name.second_author.unwrap_or_else(|| "".to_string()),
            ),
        ])?;

        self.select_plantid(&plant.name)
    }

    /// inserts a alias name, if it does not already exist. returns the id of the alias.
    pub fn create_alias(&mut self, name: &str) -> Result<i64, Error> {
        if self.create_alias_statement.is_none() {
            let stmt = self
                .conn
                .prepare("INSERT OR IGNORE INTO alias (name) VALUES (:name)")?;
            self.create_alias_statement = Some(stmt);
        };
        // println!("Creating aliasname {}", name);
        self.create_alias_statement
            .as_mut()
            .unwrap()
            .execute(&[(":name", &name)])?;

        self.select_alias_statement(&name)
    }

    /// creates a relationship between a alias name and a plant.
    pub fn relate_alias_to_plant(
        &mut self,
        alias_id: &str,
        alias_type: AliasType,
        plant_id: &str,
    ) -> Result<(), Error> {
        if self.relate_alias_to_plant_statement.is_none() {
            let stmt = self.conn.prepare("INSERT INTO plantalias (plant_id, alias_id) VALUES (:plant_id, :alias_id, :alias_type)")?;
            self.relate_alias_to_plant_statement = Some(stmt);
        };
        // println!("Relating plant {} to aliasname {}", plant_id, alias_id);
        self.relate_alias_to_plant_statement
            .as_mut()
            .unwrap()
            .execute(&[
                (":plant_id", &plant_id),
                (":alias_type", &alias_type.to_string().as_ref()),
                (":alias_id", &alias_id),
            ])?;

        Ok(())
    }

    /// creates a relationship between a plant and a region.
    pub fn create_plant_region(&mut self, plant_id: &str, region_id: &str) -> Result<i64, Error> {
        if self.create_plant_region_statement.is_none() {
            let stmt = self.conn.prepare(
                "INSERT INTO plantregion (plant_id, region_id) VALUES (:plant_id, :region_id)",
            )?;
            self.create_plant_region_statement = Some(stmt);
        };
        // println!("Creating plant region rel plant {} region {}", plant_id, region_id);
        self.create_plant_region_statement
            .as_mut()
            .unwrap()
            .execute(&[(":plant_id", &plant_id), (":region_id", &region_id)])?;

        Ok(self.conn.last_insert_rowid())
    }

    /// inserts a new region. If the region already exists this will fail.
    pub fn create_region(&mut self, name: &str, code: &str) -> Result<i64, Error> {
        if self.create_region_statement.is_none() {
            let stmt = self
                .conn
                .prepare("INSERT INTO region (name, code) VALUES (:name, :code)")?;
            self.create_region_statement = Some(stmt);
        };
        // println!("Creating region {} - {}", name, code);
        self.create_region_statement
            .as_mut()
            .unwrap()
            .execute(&[(":name", &name), (":code", &code)])?;

        Ok(self.conn.last_insert_rowid())
    }
}
