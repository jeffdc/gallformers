-- Up

-- there was some bad data in the database and we need to get rid of it before we try and add uniqueness constraints
DELETE FROM species where id IN (46, 366);

-- add uniqueness to all of the primary non-id fields for all of the data tables
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
    color TEXT UNIQUE NOT NULL
);
INSERT INTO color (id, color)
    SELECT id, color
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
    description TEXT,
    reference TEXT
);
INSERT INTO abundance (id, abundance, description, reference)
    SELECT id, abundance, description, reference 
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
    name TEXT UNIQUE NOT NULL,
    description TEXT
);
INSERT INTO family (id, name, description)
    SELECT id, name, description 
    FROM _family_old;


ALTER TABLE species RENAME TO _species_old;
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

-- now we have to drop and re-add all the tables that have foreign key dependencies on any of the tables that we just
-- modified, or that are dependent on any of these tables. Why you may ask? Because sqlite "helpful" updates all of the
-- foreign keys when you rename a table. :(
ALTER TABLE gall RENAME TO _gall_old;
CREATE TABLE gall (
    id           INTEGER PRIMARY KEY
                         NOT NULL,
    species_id   INTEGER NOT NULL,
    taxoncode    TEXT    NOT NULL
                         CHECK (taxoncode = 'gall'),
    detachable   INTEGER,-- boolean: 0 = false; 1 = true, standard sqlite
    alignment_id INTEGER,
    walls_id     INTEGER,
    cells_id     INTEGER,
    color_id     INTEGER,
    shape_id     INTEGER,
    FOREIGN KEY (
        species_id
    )
    REFERENCES species (id),
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


ALTER TABLE galllocation RENAME TO _galllocation_old;
CREATE TABLE galllocation (
    id          INTEGER PRIMARY KEY
                        NOT NULL,
    gall_id     INTEGER,
    location_id INTEGER,
    FOREIGN KEY (
        gall_id
    )
    REFERENCES gall (id),
    FOREIGN KEY (
        location_id
    )
    REFERENCES location (id) 
);
INSERT INTO galllocation (id, gall_id, location_id)
    SELECT id, gall_id, location_id 
    FROM _galllocation_old;


ALTER TABLE galltexture RENAME TO _galltexture_old;
CREATE TABLE galltexture (
    id         INTEGER PRIMARY KEY
                       NOT NULL,
    gall_id    INTEGER,
    texture_id INTEGER,
    FOREIGN KEY (
        gall_id
    )
    REFERENCES gall (id),
    FOREIGN KEY (
        texture_id
    )
    REFERENCES texture (id) 
);
INSERT INTO galltexture (id, gall_id, texture_id)
    SELECT id, gall_id, texture_id 
    FROM _galltexture_old;


ALTER TABLE host RENAME TO _host_old;
CREATE TABLE host (
    id              INTEGER PRIMARY KEY
                            NOT NULL,
    host_species_id INTEGER,
    gall_species_id INTEGER,
    FOREIGN KEY (
        host_species_id
    )
    REFERENCES species (id),
    FOREIGN KEY (
        gall_species_id
    )
    REFERENCES species (id) 
);
INSERT INTO host (id, host_species_id, gall_species_id)
    SELECT id, host_species_id, gall_species_id 
    FROM _host_old;

ALTER TABLE speciessource RENAME TO _speciessource_old;
CREATE TABLE speciessource (
    id          INTEGER PRIMARY KEY
                        NOT NULL,
    species_id  INTEGER,
    source_id   INTEGER,
    -- THIS IS A NEW column add the ability to add a description extract from a source to a source-species relationship
    description TEXT    DEFAULT '',
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

PRAGMA foreign_keys=ON;


-- added some data to the property tables - were added by hand but want to keep track here.
-- INSERT INTO abundance VALUES (NULL, 'abundant', '', '');
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
