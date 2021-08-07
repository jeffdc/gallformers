use crate::exporttogf::export;
use crate::importcsvs::import;
use crate::util::Res;
use crate::vascan::vascan_export;
use crate::vascan::vascan_import;
use std::env;

extern crate nom;

pub mod exporttogf;
pub mod gallformersdb;
pub mod importcsvs;
pub mod plant;
pub mod plantdb;
pub mod species;
pub mod util;
pub mod vascan;

fn help(args: Vec<String>) -> Res<()> {
    println!("Pass in a command line argument of `import` to import the USDA plant CSVs into a new database, `export` to export         previously imported plant data into the main gallformers database, or `both` to do both in order. {:?}", args);
    Ok(())
}

#[tokio::main]
async fn main() -> Res<()> {
    let args: Vec<String> = env::args().collect();

    match args[1].as_str() {
        "import" => match args[2].as_str() {
            "usda" => import().await,
            "vascan" => vascan_import().await,
            _ => help(args),
        },
        "export" => match args[2].as_str() {
            "usda" => export().await,
            "vascan" => vascan_export().await,
            _ => help(args),
        },
        _ => help(args),
    }
}
