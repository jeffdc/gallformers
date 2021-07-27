#[derive(Debug)]
pub struct Species {
    pub id: i64,
    pub name: String,
}

#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub struct SpeciesName {
    pub genus: String,
    pub specific: String,
    pub ssp: Option<String>,
    pub hybrid: bool,
}

impl SpeciesName {
    pub fn new(name: String) -> Self {
        let splits = name.split_whitespace().collect::<Vec<&str>>();
        let g = splits[0];
        let mut sp = splits[1];
        let mut hybrid = false;
        if sp == "x" || sp == "X" {
            hybrid = true;
            sp = splits[2];
        }
        let ssp = match splits.len() {
            3 if !hybrid => Some(splits[2].to_string()),
            _ => None,
        };

        SpeciesName {
            genus: g.to_string(),
            specific: sp.to_string(),
            ssp,
            hybrid,
        }
    }

    pub fn species_name(&mut self) -> String {
        format!("{} {}", self.genus, self.specific)
    }
}

#[test]
fn test_to_name() {
    assert_eq!(
        SpeciesName::new("Foo bar".to_string()),
        SpeciesName {
            genus: "Foo".to_string(),
            specific: "bar".to_string(),
            ssp: None,
            hybrid: false
        }
    );
    assert_eq!(
        SpeciesName::new("Foo x bar".to_string()),
        SpeciesName {
            genus: "Foo".to_string(),
            specific: "bar".to_string(),
            ssp: None,
            hybrid: true
        }
    );
    assert_eq!(
        SpeciesName::new("Foo bar baz".to_string()),
        SpeciesName {
            genus: "Foo".to_string(),
            specific: "bar".to_string(),
            ssp: Some("baz".to_string()),
            hybrid: false
        }
    );
}
