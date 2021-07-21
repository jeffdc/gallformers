use rusqlite::{Connection, Error, Statement};

/// simple context struct to manage the DB connection and prepared statements
pub struct GallformersDB<'a> {
    pub conn: &'a Connection,
    // create_plant_statement: Option<Statement<'a>>,
    host_exists_statement: Option<Statement<'a>>,
}

impl<'a> GallformersDB<'a> {
    pub fn new(conn: &'a Connection) -> Self {
        GallformersDB {
            conn,
            // create_plant_statement: None,
            host_exists_statement: None,
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

    // /// inserts a plant, if it does not already exist. uniqueness is determined by name. returns the id of the plant.
    // pub fn create_plant(&mut self, plant: &PlantCSV) -> Result<i64, Error> {
    //     if let None = &self.create_plant_statement {
    //         let stmt = self.connection.unwrap().prepare("INSERT OR IGNORE INTO plant (name, symbol, symbolsynonym, family) VALUES (:name, :symbol, :symbolsynonym, :family)")?;
    //         self.create_plant_statement = Some(stmt);
    //     };
    //     // println!("Creating plant {:?}", plant);
    //     self.create_plant_statement.as_mut().unwrap().execute(&[(":name", &plant.name), (":symbol", &plant.symbol), (":symbolsynonym", &plant.syn_symbol), (":family", &plant.family)])?;

    //     return self.select_plantid(&plant.name);
    // }
}
