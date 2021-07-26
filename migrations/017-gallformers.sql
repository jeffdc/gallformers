
-- Up

PRAGMA foreign_keys=OFF;

-- #46 - add place (ranges/regions) to species
CREATE TABLE place (
    id INTEGER PRIMARY KEY NOT NULL,
    name TEXT UNIQUE NOT NULL,
    code TEXT NOT NULL,
    type TEXT NOT NULL CHECK (type IN ("continent", "country", "region", "state", "province", "county", "city") )
);

CREATE TABLE placeplace (
    place_id INTEGER,
    parent_id INTEGER,
    FOREIGN KEY (place_id) REFERENCES place (id) ON DELETE CASCADE,
    FOREIGN KEY (parent_id) REFERENCES place (id) ON DELETE CASCADE,
    PRIMARY KEY (place_id, parent_id)

);

CREATE TABLE speciesplace (
    species_id INTEGER,
    place_id INTEGER,
    FOREIGN KEY (species_id) REFERENCES species (id) ON DELETE CASCADE,
    FOREIGN KEY (place_id) REFERENCES place (id) ON DELETE CASCADE,
    PRIMARY KEY (species_id, place_id)
);

-- add the default data
INSERT INTO place (name, code, type) VALUES ("North America", "NA", "continent");
INSERT INTO place (name, code, type) VALUES ("United States", "US", "country");
INSERT INTO place (name, code, type) VALUES ("Canada", "CA", "country");
INSERT INTO placeplace (place_id, parent_id) 
    SELECT id as child,
        (SELECT id FROM place WHERE name = "North America") AS parent
    FROM place WHERE name = "United States";
INSERT INTO placeplace (place_id, parent_id) 
    SELECT id as child,
        (SELECT id FROM place WHERE name = "North America") AS parent
    FROM place WHERE name = "Canada";

INSERT INTO place (type, code, name) VALUES ("state", "AL", "Alabama");
INSERT INTO place (type, code, name) VALUES ("state", "AK", "Alaska");
INSERT INTO place (type, code, name) VALUES ("state", "AS", "American Samoa");
INSERT INTO place (type, code, name) VALUES ("state", "AZ", "Arizona");
INSERT INTO place (type, code, name) VALUES ("state", "AR", "Arkansas");
INSERT INTO place (type, code, name) VALUES ("state", "CA", "California");
INSERT INTO place (type, code, name) VALUES ("state", "CO", "Colorado");
INSERT INTO place (type, code, name) VALUES ("state", "CT", "Connecticut");
INSERT INTO place (type, code, name) VALUES ("state", "DE", "Delaware");
INSERT INTO place (type, code, name) VALUES ("state", "DC", "District Of Columbia");
INSERT INTO place (type, code, name) VALUES ("state", "FM", "Federated States Of Micronesia");
INSERT INTO place (type, code, name) VALUES ("state", "FL", "Florida");
INSERT INTO place (type, code, name) VALUES ("state", "GA", "Georgia");
INSERT INTO place (type, code, name) VALUES ("state", "GU", "Guam");
INSERT INTO place (type, code, name) VALUES ("state", "HI", "Hawaii");
INSERT INTO place (type, code, name) VALUES ("state", "ID", "Idaho");
INSERT INTO place (type, code, name) VALUES ("state", "IL", "Illinois");
INSERT INTO place (type, code, name) VALUES ("state", "IN", "Indiana");
INSERT INTO place (type, code, name) VALUES ("state", "IA", "Iowa");
INSERT INTO place (type, code, name) VALUES ("state", "KS", "Kansas");
INSERT INTO place (type, code, name) VALUES ("state", "KY", "Kentucky");
INSERT INTO place (type, code, name) VALUES ("state", "LA", "Louisiana");
INSERT INTO place (type, code, name) VALUES ("state", "ME", "Maine");
INSERT INTO place (type, code, name) VALUES ("state", "MH", "Marshall Islands");
INSERT INTO place (type, code, name) VALUES ("state", "MD", "Maryland");
INSERT INTO place (type, code, name) VALUES ("state", "MA", "Massachusetts");
INSERT INTO place (type, code, name) VALUES ("state", "MI", "Michigan");
INSERT INTO place (type, code, name) VALUES ("state", "MN", "Minnesota");
INSERT INTO place (type, code, name) VALUES ("state", "MS", "Mississippi");
INSERT INTO place (type, code, name) VALUES ("state", "MO", "Missouri");
INSERT INTO place (type, code, name) VALUES ("state", "MT", "Montana");
INSERT INTO place (type, code, name) VALUES ("state", "NE", "Nebraska");
INSERT INTO place (type, code, name) VALUES ("state", "NV", "Nevada");
INSERT INTO place (type, code, name) VALUES ("state", "NH", "New Hampshire");
INSERT INTO place (type, code, name) VALUES ("state", "NJ", "New Jersey");
INSERT INTO place (type, code, name) VALUES ("state", "NM", "New Mexico");
INSERT INTO place (type, code, name) VALUES ("state", "NY", "New York");
INSERT INTO place (type, code, name) VALUES ("state", "NC", "North Carolina");
INSERT INTO place (type, code, name) VALUES ("state", "ND", "North Dakota");
INSERT INTO place (type, code, name) VALUES ("state", "MP", "Northern Mariana Islands");
INSERT INTO place (type, code, name) VALUES ("state", "OH", "Ohio");
INSERT INTO place (type, code, name) VALUES ("state", "OK", "Oklahoma");
INSERT INTO place (type, code, name) VALUES ("state", "OR", "Oregon");
INSERT INTO place (type, code, name) VALUES ("state", "PW", "Palau");
INSERT INTO place (type, code, name) VALUES ("state", "PA", "Pennsylvania");
INSERT INTO place (type, code, name) VALUES ("state", "PR", "Puerto Rico");
INSERT INTO place (type, code, name) VALUES ("state", "RI", "Rhode Island");
INSERT INTO place (type, code, name) VALUES ("state", "SC", "South Carolina");
INSERT INTO place (type, code, name) VALUES ("state", "SD", "South Dakota");
INSERT INTO place (type, code, name) VALUES ("state", "TN", "Tennessee");
INSERT INTO place (type, code, name) VALUES ("state", "TX", "Texas");
INSERT INTO place (type, code, name) VALUES ("state", "UT", "Utah");
INSERT INTO place (type, code, name) VALUES ("state", "VT", "Vermont");
INSERT INTO place (type, code, name) VALUES ("state", "VI", "Virgin Islands");
INSERT INTO place (type, code, name) VALUES ("state", "VA", "Virginia");
INSERT INTO place (type, code, name) VALUES ("state", "WA", "Washington");
INSERT INTO place (type, code, name) VALUES ("state", "WV", "West Virginia");
INSERT INTO place (type, code, name) VALUES ("state", "WI", "Wisconsin");
INSERT INTO place (type, code, name) VALUES ("state", "WY", "Wyoming");
INSERT INTO place (type, code, name) VALUES ("province", "AB", "Alberta");
INSERT INTO place (type, code, name) VALUES ("province", "BC", "British Columbia");
INSERT INTO place (type, code, name) VALUES ("province", "MB", "Manitoba");
INSERT INTO place (type, code, name) VALUES ("province", "NB", "New Brunswick");
INSERT INTO place (type, code, name) VALUES ("province", "NL", "Newfoundland and Labrador");
INSERT INTO place (type, code, name) VALUES ("province", "NT", "Northwest Territories");
INSERT INTO place (type, code, name) VALUES ("province", "NS", "Nova Scotia");
INSERT INTO place (type, code, name) VALUES ("province", "NU", "Nunavut");
INSERT INTO place (type, code, name) VALUES ("province", "ON", "Ontario");
INSERT INTO place (type, code, name) VALUES ("province", "PE", "Prince Edward Island");
INSERT INTO place (type, code, name) VALUES ("province", "QC", "Quebec");
INSERT INTO place (type, code, name) VALUES ("province", "SK", "Saskatchewan");
INSERT INTO place (type, code, name) VALUES ("province", "YT", "Yukon Territory");

INSERT INTO placeplace (place_id, parent_id)
    SELECT id as child,
        (SELECT id from place WHERE name="United States") AS parent
FROM place WHERE type ="state";

INSERT INTO placeplace (place_id, parent_id)
    SELECT id as child,
        (SELECT id from place WHERE name="Canada") AS parent
FROM place WHERE type ="province";

PRAGMA foreign_keys=ON;
VACUUM;

--------------------------------------------------------------
-- Down
PRAGMA foreign_keys=OFF;


PRAGMA foreign_keys=ON;

