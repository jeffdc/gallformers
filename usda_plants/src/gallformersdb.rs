use crate::species::Species;
use crate::util::Region;
use rusqlite::{Connection, Error, Statement};
use std::collections::HashMap;
use std::convert::TryInto;

#[derive(Debug, Eq, Hash, PartialEq)]
pub struct PlantSpecies {
    id: u32,
    name: String,
}

/// simple context struct to manage the DB connection and prepared statements
pub struct GallformersDB<'a> {
    pub conn: &'a Connection,
    host_exists_statement: Option<Statement<'a>>,
    add_place_for_plant_statement: Option<Statement<'a>>,
    create_place_statement: Option<Statement<'a>>,
    select_place_by_name_statement: Option<Statement<'a>>,
    create_place_place_statement: Option<Statement<'a>>,
    select_all_plants_statement: Option<Statement<'a>>,
    select_places_by_type_statement: Option<Statement<'a>>,
}

impl<'a> GallformersDB<'a> {
    pub fn new(conn: &'a Connection) -> Self {
        GallformersDB {
            conn,
            host_exists_statement: None,
            add_place_for_plant_statement: None,
            create_place_statement: None,
            select_place_by_name_statement: None,
            create_place_place_statement: None,
            select_all_plants_statement: None,
            select_places_by_type_statement: None,
        }
    }

    /// fetches an ID for a commonname by name
    pub fn host_exists(&mut self, name: &str) -> Result<bool, Error> {
        if self.host_exists_statement.is_none() {
            let stmt = self
                .conn
                .prepare("SELECT id FROM species WHERE name = :name AND taxoncode = 'plant';")?;
            self.host_exists_statement = Some(stmt);
        };
        let mut rows = self
            .host_exists_statement
            .as_mut()
            .unwrap()
            .query(&[(":name", &name)])?;
        let row = rows.next()?;
        Ok(row.is_some())
    }

    pub fn select_place_by_name(&mut self, name: &str) -> Result<Option<Region>, Error> {
        if self.select_place_by_name_statement.is_none() {
            let stmt = self
                .conn
                .prepare("SELECT id, name, code, type FROM place WHERE name = :name;")?;
            self.select_place_by_name_statement = Some(stmt);
        }
        let mut rows = self
            .select_place_by_name_statement
            .as_mut()
            .unwrap()
            .query_map(&[(":name", &name)], {
                |r| {
                    Ok(Region {
                        id: r.get(0)?,
                        name: r.get(1)?,
                        code: r.get(2)?,
                        typ: r.get(3)?,
                    })
                }
            })?;
        rows.next().transpose()
    }

    pub fn create_or_fetch_place(&mut self, region: &Region) -> Result<i64, Error> {
        if self.create_place_statement.is_none() {
            let stmt = self.conn.prepare(
                "INSERT OR IGNORE INTO place (name, code, type) VALUES (:name, :code, :type);",
            )?;
            self.create_place_statement = Some(stmt);
        }
        let r = self.create_place_statement.as_mut().unwrap().execute(&[
            (":name", &region.name),
            (":code", &region.code),
            (":type", &region.typ),
        ])?;
        match r {
            0 => Ok(self.select_place_by_name(&region.name)?.unwrap().id),
            id => Ok(id.try_into().unwrap()),
        }
    }

    pub fn add_place_for_plant(&mut self, species_id: i64, place_id: i64) -> Result<(), Error> {
        if self.add_place_for_plant_statement.is_none() {
            let stmt = self.conn.prepare(
                "INSERT OR IGNORE INTO speciesplace (species_id, place_id) VALUES (:species_id, :place_id);",
            )?;
            self.add_place_for_plant_statement = Some(stmt);
        }
        self.add_place_for_plant_statement
            .as_mut()
            .unwrap()
            .execute(&[(":species_id", &species_id), (":place_id", &place_id)])?;
        Ok(())
    }

    pub fn create_place_place(&mut self, parent_id: i64, place_id: i64) -> Result<(), Error> {
        if self.create_place_place_statement.is_none() {
            let stmt = self.conn.prepare(
                "INSERT OR IGNORE INTO placeplace (parent_id, place_id) VALUES (:parent_id, :place_id);",
            )?;
            self.create_place_place_statement = Some(stmt);
        }
        self.create_place_place_statement
            .as_mut()
            .unwrap()
            .execute(&[(":parent_id", &parent_id), (":place_id", &place_id)])?;
        Ok(())
    }

    pub fn select_all_plants(&mut self) -> Result<HashMap<String, Species>, Error> {
        if self.select_all_plants_statement.is_none() {
            let stmt = self
                .conn
                .prepare("SELECT id, name from species WHERE taxoncode = 'plant';")?;
            self.select_all_plants_statement = Some(stmt);
        }
        let rows = self
            .select_all_plants_statement
            .as_mut()
            .unwrap()
            .query_map([], |row| {
                Ok(Species {
                    id: row.get(0)?,
                    name: row.get(1)?,
                })
            })?;
        let mut species = HashMap::new();
        for p in rows {
            let plant = p?;
            species.insert(plant.name.clone(), plant);
        }
        Ok(species)
    }

    pub fn select_places_by_type(
        &mut self,
        place_type: &str,
    ) -> Result<HashMap<String, Region>, Error> {
        if self.select_places_by_type_statement.is_none() {
            let stmt = self
                .conn
                .prepare("SELECT id, name, code, type FROM place WHERE type = :place_type;")?;
            self.select_places_by_type_statement = Some(stmt);
        }
        let rows = self
            .select_places_by_type_statement
            .as_mut()
            .unwrap()
            .query_map(&[(":place_type", &place_type)], {
                |r| {
                    Ok(Region {
                        id: r.get(0)?,
                        name: r.get(1)?,
                        code: r.get(2)?,
                        typ: r.get(3)?,
                    })
                }
            })?;
        let mut rs = HashMap::new();
        for r in rows {
            let reg = r?;
            rs.insert(reg.code.clone(), reg);
        }
        Ok(rs)
    }
}
