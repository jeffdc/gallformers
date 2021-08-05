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
    accepted_name_usage_id: u32,
    #[serde(rename = "nameAccordingTo")]
    name_according_to: String,
    #[serde(rename = "nameAccordingToID")]
    name_according_to_id: String,
    #[serde(rename = "taxonomicStatus")]
    taxonomic_status: String,
    #[serde(rename = "parentNameUsageID")]
    parent_name_usage_id: Option<u32>,
    #[serde(rename = "higherClassification")]
    higher_classification: Option<String>,
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
    canonical_name: String,
    #[serde(rename = "taxonRank")]
    taxon_rank: String,
    #[serde(rename = "taxonomicAssertions")]
    taxonomic_assertions: Vec<TaxonomicAssertion>,
    #[serde(rename = "vernacularNames")]
    vernacular_names: Option<Vec<VernacularName>>,
    distribution: Option<Vec<Location>>,
}

#[derive(Deserialize, Debug)]
struct VascanResult {
    #[serde(rename = "searchedTerm")]
    searched_term: String,
    #[serde(rename = "numMatches")]
    num_matches: u32,
    matches: Option<Vec<VascanPlant>>,
}

#[derive(Deserialize, Debug)]
struct VascanResponse {
    #[serde(rename = "apiVersion")]
    api_version: String,
    #[serde(rename = "lastUpdatedDate")]
    last_updated_date: String,
    results: Vec<VascanResult>,
}

fn handle_hybrid(s: &str) -> String {
    let v: Vec<&str> = s.split(" ").collect();
    let genus = v[0];
    let species = v[1];
    format!(
        "{} {}",
        genus,
        // N.B. not an x but a multiplication sybmol ×
        match species.strip_prefix("×") {
            Some(no_x) => format!("x {}", no_x),
            None => species.to_string(),
        }
    )
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
    let places = gf_db.select_places_by_type("province")?;

    let mut count: usize = 0;
    let mut params = "".to_string();
    let total = plants.len();

    for p in &plants {
        count = count + 1;
        if params.len() < 1 {
            params = p.0.replace(" ", "%20");
        } else {
            params = format!("{}%0A{}", params, p.0.replace(" ", "%20"));
        }
        if count == 100 || count == total {
            let req_url = format!(
                "http://data.canadensys.net/vascan/api/0.1/search.json?q={plants}",
                plants = params,
            );
            let resp = client.post(&req_url).send().await?;
            let json: VascanResponse = resp.json().await?;
            for r in json.results {
                match r.matches {
                    Some(matches) => {
                        for result_plant in matches {
                            match result_plant.distribution {
                                Some(distro) => {
                                    for loc in distro {
                                        if !loc.occurrence_status.eq_ignore_ascii_case("excluded")
                                            && !loc
                                                .occurrence_status
                                                .eq_ignore_ascii_case("doubtful")
                                        {
                                            let name = handle_hybrid(&result_plant.canonical_name);
                                            match plants.get(&name) {
                                                Some(plant) => {
                                                    let locality = match loc.locality.as_str() {
                                                        "NL_N" | "NL_L" => "NL",
                                                        // for whatever reason the Canadian data includes some for what appears to be Greenland
                                                        "GL" => break,
                                                        l => l,
                                                    };
                                                    match places.get(locality) {
                                                        Some(region) => {
                                                            // println!(
                                                            //     "Adding {:?} for {:?}",
                                                            //     region, plant
                                                            // );
                                                            gf_db.add_place_for_plant(
                                                                plant.id, region.id,
                                                            )?;
                                                        }
                                                        None => {
                                                            println!(
                                                                "Failed to find locality {}.",
                                                                loc.locality
                                                            );
                                                        }
                                                    };
                                                }
                                                None => {
                                                    println!(
                                                        "Failed to find plant {}.",
                                                        result_plant.canonical_name
                                                    );
                                                }
                                            }
                                        }
                                    }
                                }
                                None => continue,
                            }
                            // we only care about a single match, some have >1 and I do not know why.
                            break;
                        }
                    }
                    None => continue,
                }
            }
            print!("#");
            count = 0;
            params = "".to_string();
        }
    }
    gf_db.conn.execute_batch("END TRANSACTION;")?;
    println!("\nFinished processing {} plants.", total);

    Ok(())
}

pub async fn vascan_export() -> Res<()> {
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_handle_hybrid() {
        assert_eq!(handle_hybrid("Quercus alba"), "Quercus alba");
        assert_eq!(handle_hybrid("Quercus ×leana"), "Quercus x leana");
    }
}
