-- Up

PRAGMA foreign_keys=OFF;

-- simplify the relationship between species and gall, make it 1-1 and store the relationship ids on boths sides
ALTER TABLE species ADD COLUMN gallid INTEGER;
UPDATE species
   SET gallid = (
           SELECT gall.id
             FROM gall
            WHERE gall.species_id = species.id
       );


-- add some NOT NULL constraints to better model our data
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


-- we want the species-gall relationship to be non-optional, this creates complexities
ALTER TABLE gall RENAME TO _gall_old;
CREATE TABLE gall (
    id           INTEGER PRIMARY KEY
                         NOT NULL,
    species_id   INTEGER NOT NULL,
    taxoncode    TEXT    NOT NULL
                         CHECK (taxoncode = 'gall'),
    detachable   INTEGER,
    alignment_id INTEGER,
    walls_id     INTEGER,
    cells_id     INTEGER,
    color_id     INTEGER,
    shape_id     INTEGER,
    FOREIGN KEY (
        species_id
    )
    REFERENCES species (id) ON DELETE CASCADE, -- if we delete the gall we want to delete the species as well
    FOREIGN KEY (
        taxonCode
    )
    REFERENCES taxontype (taxonCode),
    FOREIGN KEY (
        walls_id
    )
    REFERENCES walls (id),
    FOREIGN KEY (
        cells_id
    )
    REFERENCES cells (id),
    FOREIGN KEY (
        color_id
    )
    REFERENCES color (id),
    FOREIGN KEY (
        shape_id
    )
    REFERENCES shape (id),
    FOREIGN KEY (
        alignment_id
    )
    REFERENCES alignment (id) 
);
INSERT INTO gall (id, species_id, taxoncode, detachable, alignment_id, walls_id, cells_id, color_id, shape_id)
    SELECT id, species_id, taxoncode, detachable, alignment_id, walls_id, cells_id, color_id, shape_id 
    FROM _gall_old;

PRAGMA foreign_keys=ON;

--------------------------------------------------------------
-- Down
PRAGMA foreign_keys=OFF;

-- undo the column add
DROP TABLE source;
ALTER TABLE _source_old RENAME TO source;

DROP TABLE speciessource;
ALTER TABLE _speciessource_old RENAME TO speciessource;

DROP TABLE gall;
ALTER TABLE _gall_old RENAME TO gall;

PRAGMA foreign_keys=ON;
