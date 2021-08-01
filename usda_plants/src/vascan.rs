use crate::gallformersdb::GallformersDB;
use crate::Res;
use rusqlite::Connection;
use serde_derive::Deserialize;
use std::path::PathBuf;

#[derive(Deserialize, Debug)]
struct TaxonomicAssertion {
    #[serde(rename = "acceptedNameUsage")]
    accepted_name_usage: String,
    #[serde(rename = "acceptedNameUsageID")]
    accepte_name_usage_id: u32,
    #[serde(rename = "nameAccordingTo")]
    name_according_to: String,
    #[serde(rename = "nameAccordingToID")]
    name_according_to_id: String,
    #[serde(rename = "taxonomicStatus")]
    taxonomic_status: String,
    #[serde(rename = "parentNameUsageID")]
    parent_name_usage_id: u32,
    #[serde(rename = "higherClassification")]
    higher_classification: String,
}

#[derive(Deserialize, Debug)]
struct Location {
    #[serde(rename = "locationID")]
    location_id: String,
    locality: String,
    #[serde(rename = "establishmentMeans")]
    establishment_means: String,
    #[serde(rename = "occurrenceStatus")]
    occurrence_status: String,
}

#[derive(Deserialize, Debug)]
struct VernacularName {
    #[serde(rename = "vernacularName")]
    vernacular_name: String,
    language: String,
    source: String,
    #[serde(rename = "preferredName")]
    preferred_name: bool,
}

#[derive(Deserialize, Debug)]
struct VascanPlant {
    #[serde(rename = "taxonID")]
    taxon_id: u32,
    #[serde(rename = "scientificName")]
    scientific_name: String,
    #[serde(rename = "scientificNameAuthorship")]
    scientific_name_authorship: String,
    #[serde(rename = "canonicalName")]
    caononical_name: String,
    #[serde(rename = "taxonRank")]
    taxon_rank: String,
    #[serde(rename = "taxonomicAssertions")]
    taxonomic_assertions: Vec<TaxonomicAssertion>,
    #[serde(rename = "vernacularNames")]
    vernacular_names: Vec<VernacularName>,
    distribution: Vec<Location>,
}

#[derive(Deserialize, Debug)]
struct VascanResult {
    #[serde(rename = "searchedTerm")]
    searched_term: String,
    #[serde(rename = "numMatches")]
    num_matches: u32,
    matches: Vec<VascanPlant>,
}

#[derive(Deserialize, Debug)]
struct VascanResponse {
    #[serde(rename = "apiVersion")]
    api_version: String,
    #[serde(rename = "lastUpdatedDate")]
    last_updated_date: String,
    results: Vec<VascanResult>,
}

pub async fn vascan_import() -> Res<()> {
    let mut gf_db_file = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    gf_db_file.pop();
    gf_db_file.push("prisma/gallformers.sqlite");
    let gf_c = Connection::open(gf_db_file.as_path())?;
    let mut gf_db = GallformersDB::new(&gf_c);

    let client = reqwest::Client::builder().build()?;

    gf_db.conn.execute_batch("BEGIN TRANSACTION;")?;
    let plants = gf_db.select_all_plants()?;
    for p in plants {
        let req_url = format!(
            "http://data.canadensys.net/vascan/api/0.1/search.json?q={plant}",
            plant = p.name,
        );
        let resp = client.get(&req_url).send().await?;
        let json: VascanResponse = resp.json().await?;
        for r in json.results {
            for p in r.matches {
                for loc in p.distribution {
                    println!("loc.occurrence_status {:?}", loc.occurrence_status);
                    if !loc.occurrence_status.eq_ignore_ascii_case("excluded")
                        && !loc.occurrence_status.eq_ignore_ascii_case("doubtful")
                    {
                        println!(
                            "Adding range of {:?} for {:?}",
                            loc.locality, p.caononical_name
                        );
                    }
                }
            }
        }
    }
    gf_db.conn.execute_batch("END TRANSACTION;")?;

    Ok(())
}

pub async fn vascan_export() -> Res<()> {
    Ok(())
}
