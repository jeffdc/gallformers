use crate::exporttogf::export;
use crate::importcsvs::import;
use crate::util::Res;
use std::env;

extern crate nom;

pub mod exporttogf;
pub mod gallformersdb;
pub mod importcsvs;
pub mod plant;
pub mod plantdb;
pub mod species;
pub mod util;

fn main() -> Res<()> {
    let args: Vec<String> = env::args().collect();

    match args[1].as_str() {
        "import" => import(),
        "export" => export(),
        "both" => match import() {
            Ok(()) => export(),
            Err(err) => {
                println!("{}", err);
                Err(err)
            }
        },
        _ => {
            println!("Pass in a command line argument of `import` to import the USDA plant CSVs into a new database, `export` to export previously imported plant data into the main gallformers database, or `both` to do both in order. {:?}", args);
            Ok(())
        }
    }
}
