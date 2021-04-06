-- Up

PRAGMA foreign_keys=OFF;

-- add the the unknown family and genus as well as the relationships between the two
INSERT INTO taxonomy (id, name, description, type) VALUES (NULL, 'Unknown', 'Unknown', 'family');

INSERT INTO taxonomy (id, name, description, type, parent_id) 
    SELECT NULL, 'Unknown', 'Unknown', 'genus', id 
    FROM taxonomy WHERE name = 'Unknown' AND type='family';

INSERT INTO taxonomytaxonomy (taxonomy_id, child_id)
    SELECT parent_id, id
    FROM taxonomy WHERE name = 'Unknown' AND type = 'genus';

-- fix up bad schema, missing NOT NULL constraints on key fields
CREATE TABLE aliasspecies__ (
    species_id  INTEGER NOT NULL,
    alias_id    INTEGER NOT NULL,
    FOREIGN KEY (species_id) REFERENCES species (id) ON DELETE CASCADE,
    FOREIGN KEY (alias_id) REFERENCES alias (id) ON DELETE CASCADE,
    PRIMARY KEY (species_id, alias_id)
);
INSERT INTO aliasspecies__ (species_id, alias_id)
    SELECT species_id, alias_id 
    FROM aliasspecies;
DROP TABLE aliasspecies;
ALTER TABLE aliasspecies__ RENAME TO aliasspecies;

CREATE TABLE gallspecies__ (
    species_id  INTEGER NOT NULL,
    gall_id    INTEGER NOT NULL,
    FOREIGN KEY (species_id) REFERENCES species (id) ON DELETE CASCADE,
    FOREIGN KEY (gall_id) REFERENCES gall (id) ON DELETE CASCADE,
    PRIMARY KEY (species_id, gall_id)
);
INSERT INTO gallspecies__ (species_id, gall_id)
    SELECT species_id, gall_id 
    FROM gallspecies;
DROP TABLE gallspecies;
ALTER TABLE gallspecies__ RENAME TO gallspecies;

CREATE TABLE taxonomyalias__ (
    taxonomy_id  INTEGER NOT NULL,
    alias_id    INTEGER NOT NULL,
    FOREIGN KEY (taxonomy_id) REFERENCES taxonomy (id) ON DELETE CASCADE,
    FOREIGN KEY (alias_id) REFERENCES alias (id) ON DELETE CASCADE,
    PRIMARY KEY (taxonomy_id, alias_id)
);
INSERT INTO taxonomyalias__ (taxonomy_id, alias_id)
    SELECT taxonomy_id, alias_id 
    FROM taxonomyalias;
DROP TABLE taxonomyalias;
ALTER TABLE taxonomyalias__ RENAME TO taxonomyalias;

-- case problem in foreign key definitions. oops
CREATE TABLE gall__ (
    id          INTEGER PRIMARY KEY NOT NULL,
    taxoncode   TEXT    NOT NULL CHECK (taxoncode = 'gall'),
    detachable  INTEGER,
    undescribed BOOLEAN NOT NULL DEFAULT 0,
    FOREIGN KEY (taxoncode) REFERENCES taxontype (taxoncode) 
);
INSERT INTO gall__ (id, taxoncode, detachable, undescribed)
    SELECT id, taxoncode, detachable, undescribed
    FROM gall;
DROP TABLE gall;
ALTER TABLE gall__ RENAME TO gall;

CREATE TABLE species__ (
    id           INTEGER PRIMARY KEY NOT NULL,
    taxoncode    TEXT,
    name         TEXT    UNIQUE NOT NULL,
    datacomplete BOOLEAN DEFAULT 0 NOT NULL,
    abundance_id INTEGER,
    FOREIGN KEY (
        taxoncode
    )
    REFERENCES taxontype (taxoncode),
    FOREIGN KEY (
        abundance_id
    )
    REFERENCES abundance (id) 
);
INSERT INTO species__ (id, taxoncode, name, datacomplete, abundance_id)
    SELECT id, taxoncode, name, datacomplete, abundance_id
    FROM species;
DROP TABLE species;
ALTER TABLE species__ RENAME TO species;

-- these are all of the gall property tables, we will remove the unnecessary id and create a composite id like 
-- with the other many-to-many tables
CREATE TABLE gallcolor__ (
    gall_id  INTEGER NOT NULL,
    color_id INTEGER NOT NULL,
    FOREIGN KEY (gall_id) REFERENCES gall (id) ON DELETE CASCADE,
    FOREIGN KEY (color_id) REFERENCES color (id) ON DELETE CASCADE,
    PRIMARY KEY (gall_id, color_id)
);
INSERT INTO gallcolor__ (gall_id, color_id)
    SELECT gall_id, color_id 
    FROM gallcolor;
DROP TABLE gallcolor;
ALTER TABLE gallcolor__ RENAME TO gallcolor;

CREATE TABLE gallshape__ (
    gall_id  INTEGER NOT NULL,
    shape_id INTEGER NOT NULL,
    FOREIGN KEY (gall_id) REFERENCES gall (id) ON DELETE CASCADE,
    FOREIGN KEY (shape_id) REFERENCES shape (id) ON DELETE CASCADE,
    PRIMARY KEY (gall_id, shape_id)
);
INSERT INTO gallshape__ (gall_id, shape_id)
    SELECT gall_id, shape_id 
    FROM gallshape;
DROP TABLE gallshape;
ALTER TABLE gallshape__ RENAME TO gallshape;

CREATE TABLE gallcells__ (
    gall_id  INTEGER NOT NULL,
    cells_id INTEGER NOT NULL,
    FOREIGN KEY (gall_id) REFERENCES gall (id) ON DELETE CASCADE,
    FOREIGN KEY (cells_id) REFERENCES cells (id) ON DELETE CASCADE,
    PRIMARY KEY (gall_id, cells_id)
);
INSERT INTO gallcells__ (gall_id, cells_id)
    SELECT gall_id, cells_id 
    FROM gallcells;
DROP TABLE gallcells;
ALTER TABLE gallcells__ RENAME TO gallcells;

CREATE TABLE gallwalls__ (
    gall_id  INTEGER NOT NULL,
    walls_id INTEGER NOT NULL,
    FOREIGN KEY (gall_id) REFERENCES gall (id) ON DELETE CASCADE,
    FOREIGN KEY (walls_id) REFERENCES walls (id) ON DELETE CASCADE,
    PRIMARY KEY (gall_id, walls_id)
);
INSERT INTO gallwalls__ (gall_id, walls_id)
    SELECT gall_id, walls_id 
    FROM gallwalls;
DROP TABLE gallwalls;
ALTER TABLE gallwalls__ RENAME TO gallwalls;

CREATE TABLE gallalignment__ (
    gall_id  INTEGER NOT NULL,
    alignment_id INTEGER NOT NULL,
    FOREIGN KEY (gall_id) REFERENCES gall (id) ON DELETE CASCADE,
    FOREIGN KEY (alignment_id) REFERENCES alignment (id) ON DELETE CASCADE,
    PRIMARY KEY (gall_id, alignment_id)    
);
INSERT INTO gallalignment__ (gall_id, alignment_id)
    SELECT gall_id, alignment_id 
    FROM gallalignment;
DROP TABLE gallalignment;
ALTER TABLE gallalignment__ RENAME TO gallalignment;

CREATE TABLE galllocation__ (
    gall_id     INTEGER NOT NULL,
    location_id INTEGER NOT NULL,
    FOREIGN KEY (gall_id) REFERENCES gall (id) ON DELETE CASCADE,
    FOREIGN KEY (location_id) REFERENCES location (id),
    PRIMARY KEY (gall_id, location_id)
);
INSERT INTO galllocation__ (gall_id, location_id)
    SELECT gall_id, location_id 
    FROM galllocation;
DROP TABLE galllocation;
ALTER TABLE galllocation__ RENAME TO galllocation;

CREATE TABLE galltexture__ (
    gall_id    INTEGER NOT NULL,
    texture_id INTEGER NOT NULL,
    FOREIGN KEY (gall_id) REFERENCES gall (id) ON DELETE CASCADE,
    FOREIGN KEY (texture_id) REFERENCES texture (id),
    PRIMARY KEY (gall_id, texture_id)
);
INSERT INTO galltexture__ (gall_id, texture_id)
    SELECT gall_id, texture_id 
    FROM galltexture;
DROP TABLE galltexture;
ALTER TABLE galltexture__ RENAME TO galltexture;

-- make stuff NOT NULL
CREATE TABLE speciessource__ (
    id           INTEGER PRIMARY KEY NOT NULL,
    species_id   INTEGER NOT NULL,
    source_id    INTEGER NOT NULL,
    description  TEXT    DEFAULT '' NOT NULL,
    useasdefault INTEGER DEFAULT 0 NOT NULL,
    externallink TEXT    DEFAULT '' NOT NULL,
    alias_id     INTEGER,
    FOREIGN KEY (species_id) REFERENCES species (id) ON DELETE CASCADE,
    FOREIGN KEY (source_id) REFERENCES source (id) ON DELETE CASCADE,
    FOREIGN KEY (alias_id) REFERENCES alias (id)
);
INSERT INTO speciessource__ (id, species_id, source_id, description, useasdefault, externallink, alias_id)
    SELECT id, species_id, source_id, description, useasdefault, externallink, alias_id 
    FROM speciessource;
DROP TABLE speciessource;
ALTER TABLE speciessource__ RENAME TO speciessource;


PRAGMA foreign_keys=ON;

--------------------------------------------------------------
-- Down
PRAGMA foreign_keys=OFF;


PRAGMA foreign_keys=ON;
