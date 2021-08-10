use crate::plant::PlantCSV;
use crate::plant::PlantName;
use crate::species::SpeciesName;
use crate::util::Region;
use nom::lib::std::collections::HashSet;
use rusqlite::{Connection, Error, Statement};
use strum_macros::Display;

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
    plant_name_exists_statement: Option<Statement<'a>>,
    select_plant_regions_statement: Option<Statement<'a>>,
    select_all_regions_statement: Option<Statement<'a>>,
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
            plant_name_exists_statement: None,
            select_plant_regions_statement: None,
            select_all_regions_statement: None,
        }
    }

    pub fn plant_name_exists(&mut self, name: SpeciesName) -> Result<bool, Error> {
        if self.plant_name_exists_statement.is_none() {
            let stmt = self
                .conn
                .prepare("SELECT id FROM plant WHERE genus = :genus AND specific = :specific;")?;
            self.plant_exists_statement = Some(stmt);
        };
        let mut rows = self
            .plant_exists_statement
            .as_mut()
            .unwrap()
            .query(&[(":genus", &name.genus), (":specific", &name.specific)])?;
        let row = rows.next()?;
        Ok(row.is_some())
    }

    pub fn plant_exists(&mut self, name: &str) -> Result<bool, Error> {
        if self.plant_exists_statement.is_none() {
            let stmt = self
                .conn
                .prepare("SELECT id FROM plant WHERE rawname LIKE :rawname;")?;
            self.plant_exists_statement = Some(stmt);
        };
        let like_name = name.to_owned() + "%";
        let mut rows = self
            .plant_exists_statement
            .as_mut()
            .unwrap()
            .query(&[(":rawname", &like_name)])?;
        let row = rows.next()?;
        Ok(row.is_some())
    }

    /// fetches an ID for a Plant by name
    pub fn select_plantid(&mut self, name: &str) -> Result<i64, Error> {
        if self.select_plantid_statement.is_none() {
            let stmt = self
                .conn
                .prepare("SELECT id FROM plant WHERE rawname = :rawname;")?;
            self.select_plantid_statement = Some(stmt);
        };
        let mut rows = self
            .select_plantid_statement
            .as_mut()
            .unwrap()
            .query(&[(":rawname", &name)])?;
        let row = rows.next()?;
        let id = row
            .map(|r| r.get(0).expect("Failed to fetch plant id."))
            .expect("Failed to fetch plant id.");
        Ok(id)
    }

    /// fetches an ID for a alias by name
    pub fn select_aliasid(&mut self, name: &str) -> Result<i64, Error> {
        if self.select_aliasid_statement.is_none() {
            let stmt = self
                .conn
                .prepare("SELECT id FROM alias WHERE name = :name;")?;
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
            .expect("Failed to fetch alias id.");
        Ok(id)
    }

    pub fn select_plant_regions(&mut self, name: SpeciesName) -> Result<HashSet<Region>, Error> {
        if self.select_plant_regions_statement.is_none() {
            let stmt = self.conn.prepare(
                "SELECT r.id, 
                    r.name,
                    r.code
                FROM plant AS p
                    INNER JOIN
                    plantregion AS pr ON (pr.plant_id = p.id) 
                    INNER JOIN
                    region AS r ON (r.id = pr.region_id) 
                WHERE genus = :genus AND 
                    specific = :specific;",
            )?;
            self.select_plant_regions_statement = Some(stmt);
        };
        let rows = self
            .select_plant_regions_statement
            .as_mut()
            .unwrap()
            .query_map(
                &[(":genus", &name.genus), (":specific", &name.specific)],
                |row| {
                    Ok(Region {
                        id: row.get(0)?,
                        name: row.get(1)?,
                        code: row.get(2)?,
                        typ: "state".to_string(),
                    })
                },
            )?;

        let mut regions = HashSet::new();
        for region in rows {
            regions.insert(region?);
        }
        Ok(regions)
    }

    /// inserts a plant, if it does not already exist. uniqueness is determined by name. returns the id of the plant.
    pub fn create_plant(&mut self, plant: &PlantCSV, name: PlantName) -> Result<i64, Error> {
        if self.create_plant_statement.is_none() {
            let stmt = self.conn.prepare("INSERT OR IGNORE INTO plant (rawname, symbol, symbolsynonym, family, genus, specific, type, sspvar, hybridpair, author, secondauthor) VALUES (:rawname, :symbol, :symbolsynonym, :family, :genus, :specific, :type, :sspvar, :hybridpair, :author, :secondauthor)")?;
            self.create_plant_statement = Some(stmt);
        };
        // println!("Creating plant {:?} -- {:?}", plant, name);
        self.create_plant_statement.as_mut().unwrap().execute(&[
            (":rawname", &plant.name),
            (":symbol", &plant.symbol),
            (":symbolsynonym", &plant.syn_symbol),
            (":family", &plant.family),
            (":genus", &name.genus),
            (":specific", &name.specific),
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

        self.select_aliasid(&name)
    }

    /// creates a relationship between a alias name and a plant.
    pub fn relate_alias_to_plant(
        &mut self,
        alias_id: &str,
        alias_type: AliasType,
        plant_id: &str,
    ) -> Result<(), Error> {
        if self.relate_alias_to_plant_statement.is_none() {
            let stmt = self.conn.prepare("INSERT INTO plantalias (plant_id, alias_id, type) VALUES (:plant_id, :alias_id, :alias_type)")?;
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

    pub fn select_all_regions(&mut self) -> Result<Vec<Region>, Error> {
        if self.select_all_regions_statement.is_none() {
            let stmt = self.conn.prepare("SELECT id, name, code FROM region;")?;
            self.select_all_regions_statement = Some(stmt);
        };
        let rows = self
            .select_all_regions_statement
            .as_mut()
            .unwrap()
            .query_map([], |r| {
                Ok(Region {
                    id: r.get(0)?,
                    name: r.get(1)?,
                    code: r.get(2)?,
                    typ: "state".to_string(),
                })
            })?;

        let mut regions = Vec::new();
        for r in rows {
            regions.push(r?);
        }
        Ok(regions)
    }
}
