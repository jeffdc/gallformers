use crate::plant::parsers::parse_name;
use crate::species::SpeciesName;
use serde_derive::Deserialize;
use strum_macros::Display;

/// struct that the CSV rows will be deserialized into
/// a CSV row is: "Symbol","Synonym Symbol","Scientific Name with Author","State Common Name","Family"
#[derive(Debug, Deserialize)]
pub struct PlantCSV {
    #[serde(rename = "Symbol")]
    pub symbol: String,
    #[serde(rename = "Synonym Symbol")]
    pub syn_symbol: String,
    #[serde(rename = "Scientific Name with Author")]
    pub name: String,
    #[serde(rename = "State Common Name")]
    pub common_name: String,
    #[serde(rename = "Family")]
    pub family: String,
}

#[derive(Debug)]
pub struct Plant {
    pub id: i64,
    pub symbol: String,
    pub symbol_syn: String,
    pub name: String,
    pub family: String,
}

const VARIETY: &str = " var. ";
const SUBSPECIES: &str = " ssp. ";
const ORTH_VAR: &str = ", orth. var.";
const HYBRID_START: &str = " [";

#[derive(Clone, Display, Debug, PartialEq)]
pub enum SpeciesType {
    #[strum(serialize = "x")]
    Hybrid,
    #[strum(serialize = "sp.")]
    Species,
    #[strum(serialize = "ssp.")]
    Subspecies,
    #[strum(serialize = "var.")]
    Variety,
    #[strum(serialize = "orth. var.")]
    OrthVar,
    // other will be used if we encounter any of the taxonomy naming stuff like:
    // orth. cons. / orth. rej. / orth. var., nom. inval. / nom. inval. / nom. utique rej. / nom. illeg. / nom. nud. / nom/ inq.
    #[strum(serialize = "other")]
    Other,
}

impl Default for SpeciesType {
    fn default() -> Self {
        SpeciesType::Species
    }
}

//TODO: convert to From trait?
pub fn plant_name_to_species_name(pn: &PlantName) -> SpeciesName {
    SpeciesName {
        genus: pn.genus.to_string(),
        specific: pn.specific.to_string(),
        ssp: pn.sspvar.clone(),
        hybrid: pn.hybrid.is_some(),
    }
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct PlantName {
    pub genus: String,
    pub specific: String,
    pub species_type: SpeciesType,
    pub sspvar: Option<String>,
    pub hybrid: Option<(String, String)>,
    pub author: Option<String>,
    pub second_author: Option<String>,
}

impl<'a> PlantName {
    pub fn new(name: String) -> Result<Self, nom::error::Error<String>> {
        parse_name(&name)
    }

    pub fn species_name(&mut self) -> String {
        format!("{} {}", self.genus, self.specific)
    }
}

pub(self) mod parsers {
    use super::*;
    use nom::branch::*;
    use nom::bytes::complete::*;
    use nom::character::complete::*;
    use nom::combinator::*;
    use nom::multi::*;
    use nom::sequence::*;
    use nom::Finish;
    use nom::IResult;

    fn not_whitespace(i: &str) -> IResult<&str, &str> {
        is_not(" \t")(i)
    }

    // Parse the hybrid symbol, ×, if found.
    // N.B., the symbol is not an ASCII x but × the unicode multiplcation sign. https://codepoints.net/U+00d7
    fn is_hybrid(i: &str) -> nom::IResult<&str, &str> {
        take_while(|c| c == '×')(i)
    }

    // Parse the pair of species for a hybrid: [species1 × species2]
    // N.B., the symbol is not an ASCII x but × the unicode multiplcation sign. https://codepoints.net/U+00d7
    fn hybrid(i: &str) -> IResult<&str, (&str, &str)> {
        delimited(
            tag(HYBRID_START),
            separated_pair(alphanumeric1, tag(" × "), alphanumeric1),
            tag("]"),
        )(i)
    }

    fn sspvar(i: &str) -> IResult<&str, &str> {
        terminated(is_not(" "), multispace1)(i)
    }

    fn modifier(i: &str) -> IResult<&str, &str> {
        alt((
            tag(VARIETY),
            tag(SUBSPECIES),
            tag(ORTH_VAR),
            // preserve the opening [ to make later parsing easier
            peek(tag(HYBRID_START)),
            eof,
        ))(i)
    }

    fn second_author(i: &str) -> IResult<&str, Option<&str>> {
        opt(terminated(is_not("\n"), eof))(i)
    }

    fn parse_author(i: &str) -> IResult<&str, String> {
        let parser = many_till(
            anychar,
            alt((
                peek(tag(VARIETY)),
                peek(tag(SUBSPECIES)),
                peek(tag(ORTH_VAR)),
                peek(tag(HYBRID_START)),
                eof,
            )),
        );
        // this seems very hacky but I can not find a nom parser that will just parse chars as string until some condition,
        // so we end up with a Vec<char> since `anychar` only operates at the char level.
        map(parser, |r| {
            r.0.into_iter()
                .fold(String::new(), |mut acc, c| {
                    acc.push(c);
                    acc
                })
                .to_string()
        })(i)
    }

    fn parse_name_internal(i: &str) -> IResult<&str, PlantName> {
        let (i, genus) = not_whitespace(i)?;
        let (i, _) = nom::character::complete::space1(i)?;
        let (i, _) = is_hybrid(i)?;
        let (i, specific) = not_whitespace(i)?;
        let (i, _) = nom::character::complete::space1(i)?;
        let (i, author) = parse_author(i)?;
        let (i, species_type, hybrid, sspvar) = match modifier(i) {
            Ok((i, VARIETY)) => {
                let (ii, sv) = sspvar(i)?;
                (ii, SpeciesType::Variety, None, Some(sv.to_string()))
            }
            Ok((i, SUBSPECIES)) => {
                let (ii, sv) = sspvar(i)?;
                (ii, SpeciesType::Subspecies, None, Some(sv.to_string()))
            }
            Ok((i, HYBRID_START)) => {
                let (ii, (a, b)) = hybrid(i)?;
                (
                    ii,
                    SpeciesType::Hybrid,
                    Some((a.to_string(), b.to_string())),
                    None,
                )
            }
            Ok((i, ORTH_VAR)) => (i, SpeciesType::OrthVar, None, None),
            Ok((i, _)) => (i, SpeciesType::Species, None, None),
            // for now we are going to ignore all of the other possibilies which are all weird esoteric taxonomy naming things
            Err(_) => ("", SpeciesType::Other, None, None),
        };
        let (i, second_author) = second_author(i)?;

        Ok((
            i,
            PlantName {
                genus: genus.to_string(),
                specific: specific.to_string(),
                species_type,
                sspvar,
                hybrid,
                author: Some(author.to_string()),
                second_author: second_author.map(|a| a.to_string()),
            },
        ))
    }

    pub fn parse_name(i: &str) -> Result<PlantName, nom::error::Error<String>> {
        match parse_name_internal(i).finish() {
            Ok((_, n)) => Ok(n),
            Err(e) => Err(nom::error::Error::new(e.input.to_string(), e.code)),
        }
    }

    #[cfg(test)]
    mod tests {
        use super::*;

        #[test]
        fn test_not_whitespace() {
            assert_eq!(not_whitespace("Quercus alba"), Ok((" alba", "Quercus")));
            assert_eq!(not_whitespace("Quercus\talba"), Ok(("\talba", "Quercus")));
            assert_eq!(
                not_whitespace(" alba"),
                Err(nom::Err::Error(nom::error::Error {
                    input: " alba",
                    code: nom::error::ErrorKind::IsNot,
                }))
            );
        }

        #[test]
        fn test_is_hybrid() {
            assert_eq!(is_hybrid("×leana"), Ok(("leana", "×")));
            assert_eq!(is_hybrid("alba"), Ok(("alba", "")));
        }

        #[test]
        fn test_hybrid() {
            assert_eq!(
                hybrid(" [alba × michauxii]"),
                Ok(("", ("alba", "michauxii")))
            );
            assert_eq!(
                hybrid("Foo bar"),
                Err(nom::Err::Error(nom::error::Error {
                    input: "Foo bar",
                    code: nom::error::ErrorKind::Tag,
                }))
            );
            assert!(hybrid(" []").is_err());
            assert!(hybrid(" [alba michauxii]").is_err());
            assert!(hybrid(" [alba x michauxii]").is_err());
        }

        #[test]
        fn test_parse_author() {
            assert_eq!(parse_author("L."), Ok(("", "L.".to_string())));
            assert_eq!(
                parse_author("L. [foo x bar]"),
                Ok((" [foo x bar]", "L.".to_string()))
            );
            assert_eq!(
                parse_author("L. var. foo"),
                Ok((" var. foo", "L.".to_string()))
            );
            assert_eq!(
                parse_author("L. ssp. foo"),
                Ok((" ssp. foo", "L.".to_string()))
            );
            assert_eq!(
                parse_author("L., orth. var."),
                Ok((ORTH_VAR, "L.".to_string()))
            );
            assert_eq!(parse_author("Foo bar"), Ok(("", "Foo bar".to_string())));
            assert_eq!(
                parse_author("Foo bar var. baz"),
                Ok((" var. baz", "Foo bar".to_string()))
            );
            assert_eq!(
                parse_author("Foo bar ssp. baz"),
                Ok((" ssp. baz", "Foo bar".to_string()))
            );
            assert_eq!(
                parse_author("Foo bar, orth. var."),
                Ok((ORTH_VAR, "Foo bar".to_string()))
            );
        }

        #[test]
        fn test_modifier() {
            assert_eq!(modifier(""), Ok(("", "")));
            assert_eq!(modifier(ORTH_VAR), Ok(("", ORTH_VAR)));
            assert_eq!(modifier(" ssp. foo"), Ok(("foo", SUBSPECIES)));
            assert_eq!(modifier(" var. foo"), Ok(("foo", VARIETY)));
            assert_eq!(
                modifier(" [alba x michauxii]"),
                Ok((" [alba x michauxii]", HYBRID_START))
            );
        }

        #[test]
        fn test_sspvar() {
            assert_eq!(sspvar("foo "), Ok(("", "foo")));
            assert_eq!(sspvar("foo bar"), Ok(("bar", "foo")));
        }

        #[test]
        fn test_second_author() {
            assert_eq!(
                second_author("A.L. Pickens & M.C. Pickens"),
                Ok(("", Some("A.L. Pickens & M.C. Pickens")))
            );
            assert_eq!(second_author(""), Ok(("", None)));
        }

        #[test]
        fn test_parse_name() {
            assert_eq!(
                parse_name("Quercus alba L."),
                Ok(PlantName {
                    genus: "Quercus".to_string(),
                    specific: "alba".to_string(),
                    author: Some("L.".to_string()),
                    ..Default::default()
                })
            );

            assert_eq!(
                parse_name("Quercus alba L. var. subcaerulea A.L. Pickens & M.C. Pickens"),
                Ok(PlantName {
                    genus: "Quercus".to_string(),
                    specific: "alba".to_string(),
                    author: Some("L.".to_string()),
                    species_type: SpeciesType::Variety,
                    sspvar: Some("subcaerulea".to_string()),
                    second_author: Some("A.L. Pickens & M.C. Pickens".to_string()),
                    ..Default::default()
                })
            );

            assert_eq!(
                parse_name(
                    "Ruellia caroliniensis (J.F. Gmel.) Steud. ssp. ciliosa (Pursh) R.W. Long"
                ),
                Ok(PlantName {
                    genus: "Ruellia".to_string(),
                    specific: "caroliniensis".to_string(),
                    species_type: SpeciesType::Subspecies,
                    sspvar: Some("ciliosa".to_string()),
                    hybrid: None,
                    author: Some("(J.F. Gmel.) Steud.".to_string()),
                    second_author: Some("(Pursh) R.W. Long".to_string()),
                })
            );

            assert_eq!(
                parse_name("Quercus ×beadlei Trel. ex Palmer [alba × michauxii]"),
                Ok(PlantName {
                    genus: "Quercus".to_string(),
                    specific: "beadlei".to_string(),
                    species_type: SpeciesType::Hybrid,
                    sspvar: None,
                    hybrid: Some(("alba".to_string(), "michauxii".to_string())),
                    author: Some("Trel. ex Palmer".to_string()),
                    second_author: None,
                })
            );

            assert_eq!(
                parse_name("Acaena novae-zelandica Kirk, orth. var."),
                Ok(PlantName {
                    genus: "Acaena".to_string(),
                    specific: "novae-zelandica".to_string(),
                    species_type: SpeciesType::OrthVar,
                    sspvar: None,
                    hybrid: None,
                    author: Some("Kirk".to_string()),
                    second_author: None,
                })
            );
        }
    }
}
