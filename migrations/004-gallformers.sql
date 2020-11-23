-- Up

PRAGMA foreign_keys=OFF;

ALTER TABLE source RENAME TO _source_old;
CREATE TABLE source (
    id       INTEGER PRIMARY KEY
                     NOT NULL,
    title    TEXT    UNIQUE
                     NOT NULL,
    author   TEXT   NOT NULL, -- add NOT NULL in 004
    pubyear  TEXT NOT NULL, -- add NOT NULL in 004
    link     TEXT NOT NULL, -- add NOT NULL in 004
    citation TEXT NOT NULL -- add NOT NULL in 004
);
INSERT INTO source (id, title, author, pubyear, link, citation)
    SELECT id, title, author, pubyear, link, citation 
    FROM _source_old;


ALTER TABLE speciessource RENAME TO _speciessource_old;
CREATE TABLE speciessource (
    id          INTEGER PRIMARY KEY
                        NOT NULL,
    species_id  INTEGER NOT NULL, -- add NOT NULL in 004
    source_id   INTEGER NOT NULL, -- add NOT NULL in 004
    description TEXT    DEFAULT '',
    -- add a column to speciessource to track the "default" description that applies to the species
    useasdefault INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (
        species_id
    )
    REFERENCES species (id),
    FOREIGN KEY (
        source_id
    )
    REFERENCES source (id) 
);
INSERT INTO speciessource (id, species_id, source_id, description)
    SELECT id, species_id, source_id, description 
    FROM _speciessource_old;

PRAGMA foreign_keys=ON;

--------------------------------------------------------------
-- Down
PRAGMA foreign_keys=OFF;

-- undo the column add
DROP TABLE source;
ALTER TABLE _source_old RENAME TO source;

DROP TABLE speciessource;
ALTER TABLE _speciessource_old RENAME TO speciessource;

PRAGMA foreign_keys=ON;
