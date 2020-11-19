-- Up

-- add uniquness to all of the primary non-id fields for all of the data tables
-- N.B. Sqlite does not allow adding a constraint to an already existing table, so we have to create new tables,
-- rename the old ones, and then migrate the data.
PRAGMA foreign_keys=OFF;
ALTER TABLE location RENAME TO _location_old;
CREATE TABLE location (
    id INTEGER PRIMARY KEY NOT NULL,
    location TEXT UNIQUE NOT NULL,
    description TEXT
);
INSERT INTO location (id, location, description)
    SELECT id, location, description 
    FROM _location_old;


ALTER TABLE texture RENAME TO _texture_old;
CREATE TABLE texture (
    id INTEGER PRIMARY KEY NOT NULL,
    texture TEXT UNIQUE NOT NULL,
    description TEXT
);
INSERT INTO texture (id, texture, description)
    SELECT id, texture, description 
    FROM _texture_old;


ALTER TABLE walls RENAME TO _walls_old;
CREATE TABLE walls (
    id INTEGER PRIMARY KEY NOT NULL,
    walls TEXT UNIQUE NOT NULL,
    description TEXT
);
INSERT INTO walls (id, walls, description)
    SELECT id, walls, description 
    FROM _walls_old;


ALTER TABLE cells RENAME TO _cells_old;
CREATE TABLE cells (
    id INTEGER PRIMARY KEY NOT NULL,
    cells TEXT UNIQUE NOT NULL,
    description TEXT
);
INSERT INTO cells (id, cells, description)
    SELECT id, cells, description 
    FROM _cells_old;


ALTER TABLE color RENAME TO _color_old;
CREATE TABLE color (
    id INTEGER PRIMARY KEY NOT NULL,
    color TEXT UNIQUE NOT NULL,
    description TEXT
);
INSERT INTO color (id, color, description)
    SELECT id, color, description 
    FROM _color_old;


ALTER TABLE alignment RENAME TO _alignment_old;
CREATE TABLE alignment (
    id INTEGER PRIMARY KEY NOT NULL,
    alignment TEXT UNIQUE NOT NULL,
    description TEXT
);
INSERT INTO alignment (id, alignment, description)
    SELECT id, alignment, description 
    FROM _alignment_old;


ALTER TABLE shape RENAME TO _shape_old;
CREATE TABLE shape (
    id INTEGER PRIMARY KEY NOT NULL,
    shape TEXT UNIQUE NOT NULL,
    description TEXT
);
INSERT INTO shape (id, shape, description)
    SELECT id, shape, description 
    FROM _shape_old;


ALTER TABLE abundance RENAME TO _abundance_old;
CREATE TABLE abundance (
    id INTEGER PRIMARY KEY NOT NULL,
    abundance TEXT UNIQUE NOT NULL,
    description TEXT
);
INSERT INTO abundance (id, abundance, description)
    SELECT id, abundance, description 
    FROM _abundance_old;


ALTER TABLE taxontype RENAME TO _taxontype_old;
CREATE TABLE taxontype (
    taxoncode   TEXT PRIMARY KEY NOT NULL,
    description TEXT UNIQUE NOT NULL
);
INSERT INTO taxontype (taxoncode, description)
    SELECT taxoncode, description 
    FROM _taxontype_old;


ALTER TABLE family RENAME TO _family_old;
CREATE TABLE family (
    id INTEGER PRIMARY KEY NOT NULL,
    name TEXT UNIQUE,
    description TEXT
);
INSERT INTO family (id, name, description)
    SELECT id, name, description 
    FROM _family_old;


ALTER species RENAME TO _species_old;
CREATE TABLE species (
    id           INTEGER PRIMARY KEY NOT NULL,
    taxoncode    TEXT,
    name         TEXT UNIQUE NOT NULL,
    synonyms     TEXT,
    commonnames  TEXT,
    genus        TEXT    NOT NULL,
    family_id    INTEGER NOT NULL,
    description  TEXT,
    abundance_id INTEGER,
    FOREIGN KEY (
        taxoncode
    )
    REFERENCES taxontype (taxonCode),
    FOREIGN KEY (
        abundance_id
    )
    REFERENCES abundance (id),
    FOREIGN KEY (
        family_id
    )
    REFERENCES family (id)
);
INSERT INTO species (id, taxoncode, name, synonyms, commonnames, genus, family_id, description, abundance_id)
    SELECT id, taxoncode, name, synonyms, commonnames, genus, family_id, description, abundance_id 
    FROM _species_old;


PRAGMA foreign_keys=ON;


-- add the ability to add a description extract from a source to a source-species relationship
ALTER TABLE speciessource ADD COLUMN description TEXT DEFAULT '';

-- added some data to the property tables
-- INSERT INTO abundance VALUES (NULL, 'adundant', '', '');
-- INSERT INTO abundance VALUES (NULL, 'common', '', '');
-- INSERT INTO abundance VALUES (NULL, 'frequent', '', '');
-- INSERT INTO abundance VALUES (NULL, 'occasional', '', '');
-- INSERT INTO abundance VALUES (NULL, 'rare', '', '');

-- INSERT INTO location VALUES(NULL, 'stem', '');

--------------------------------------------------------------
-- Down
PRAGMA foreign_keys=OFF;

DROP TABLE location;
ALTER TABLE _location_old RENAME TO location;

DROP TABLE texture;
ALTER TABLE _texture_old RENAME TO texture;

DROP TABLE walls;
ALTER TABLE _walls_old RENAME TO walls;

DROP TABLE cells;
ALTER TABLE _cells_old RENAME TO cells;

DROP TABLE color;
ALTER TABLE _color_old RENAME TO color;

DROP TABLE alignment;
ALTER TABLE _alignment_old RENAME TO alignment;

DROP TABLE shape;
ALTER TABLE _shape_old RENAME TO shape;

DROP TABLE abundance;
ALTER TABLE _abundance_old RENAME TO abundance;

DROP TABLE taxontype;
ALTER TABLE _taxontype_old RENAME TO taxontype;

DROP TABLE family;
ALTER TABLE _family_old RENAME TO family;

DROP TABLE species;
ALTER TABLE _species_old RENAME TO species;

-- We can not drop the column that was created on speciessource as sqlite has no ability to delete a column
-- other than to create a new table and migrate data.
ALTER TABLE speciessource RENAME TO _speciessource_old;
CREATE TABLE speciessource (
    id         INTEGER PRIMARY KEY NOT NULL,
    species_id INTEGER,
    source_id  INTEGER,
    FOREIGN KEY (
        species_id
    )
    REFERENCES species (id),
    FOREIGN KEY (
        source_id
    )
    REFERENCES source (id) 
);
INSERT INTO speciessource (id, species_id, source_id)
    SELECT id, species_id, source_id 
    FROM _speciessource_old;
DROP TABLE _speciessource_old;

PRAGMA foreign_keys=ON;
