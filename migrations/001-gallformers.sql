-- Up

-- These are static tables that hold various constants and what not. While it is tempting to slam them
-- all together into one giant lookup table this leads to other problems.. see: https://www.red-gate.com/simple-talk/sql/database-administration/five-simple-database-design-errors-you-should-avoid/
CREATE TABLE location(
    id INTEGER PRIMARY KEY NOT NULL,
    location TEXT,
    description TEXT
);

CREATE TABLE texture(
    id INTEGER PRIMARY KEY NOT NULL,
    texture text,
    description TEXT
);

CREATE TABLE color(
    id INTEGER PRIMARY KEY NOT NULL,
    color text
);

CREATE TABLE walls(
    id INTEGER PRIMARY KEY NOT NULL,
    walls text,
    description TEXT
);

CREATE TABLE cells(
    id INTEGER PRIMARY KEY NOT NULL,
    cells text,
    description TEXT
);

CREATE TABLE alignment(
    id INTEGER PRIMARY KEY NOT NULL,
    alignment text,
    description TEXT
);

CREATE TABLE shape(
    id INTEGER PRIMARY KEY NOT NULL,
    shape text,
    description TEXT
);

CREATE TABLE abundance(
    id INTEGER PRIMARY KEY NOT NULL,
    abundance TEXT,
    description TEXT,
    reference TEXT -- URL to 
);

-- this is a table that allows us to use Vertical Disjunctive Partitioning (VDP) table partitioning for tracking
-- extra details about particular groups of taxa, e.g., galls in our current case 
-- See: https://wiki.postgresql.org/images/a/ad/Hierarchial.pdf
CREATE TABLE taxontype(
    taxoncode TEXT PRIMARY KEY NOT NULL,
    description TEXT NOT NULL
);

CREATE TABLE family(
    id INTEGER PRIMARY KEY NOT NULL,
    name TEXT,
    description TEXT
);

CREATE TABLE species(
    id INTEGER PRIMARY KEY NOT NULL,
    taxoncode TEXT,
    name TEXT NOT NULL, -- this is the accepted binomial 'Genus species' name
    synonyms TEXT, -- CSV text
    commonnames TEXT, -- CSV text
    genus TEXT NOT NULL,
    family_id INTEGER NOT NULL,
    description TEXT,
    abundance_id INTEGER,
    FOREIGN KEY(taxoncode) REFERENCES taxontype(taxonCode),
    FOREIGN KEY(abundance_id) REFERENCES abundance(id),
    FOREIGN KEY(family_id) REFERENCES family(id)
);

CREATE TABLE gall(
    id INTEGER PRIMARY KEY NOT NULL,
    species_id INTEGER NOT NULL,
    taxoncode TEXT NOT NULL CHECK (taxoncode = 'gall'),
    detachable INTEGER, -- boolean: 0 = false; 1 = true, standard sqlite
    alignment_id INTEGER,
    walls_id INTEGER,
    cells_id INTEGER,
    color_id INTEGER,
    shape_id INTEGER,
    FOREIGN KEY(species_id) REFERENCES species(id)
    FOREIGN KEY(taxonCode) REFERENCES taxontype(taxonCode)
    FOREIGN KEY(walls_id) REFERENCES walls(id)
    FOREIGN KEY(cells_id) REFERENCES walls(id)
    FOREIGN KEY(color_id) REFERENCES color(id)
    FOREIGN KEY(shape_id) REFERENCES shape(id)
    FOREIGN KEY(alignment_id) REFERENCES alignment(id)
);

CREATE TABLE galllocation(
    id INTEGER PRIMARY KEY NOT NULL,
    gall_id INTEGER,
    location_id INTEGER,
    FOREIGN KEY(gall_id) REFERENCES gall(id),
    FOREIGN KEY(location_id) REFERENCES location(id)
);

CREATE TABLE galltexture(
    id INTEGER PRIMARY KEY NOT NULL,
    gall_id INTEGER,
    texture_id INTEGER,
    FOREIGN KEY(gall_id) REFERENCES gall(id),
    FOREIGN KEY(texture_id) REFERENCES texture(id)
);

-- a host is just a many-to-many relationship between species
CREATE TABLE host(
    id INTEGER PRIMARY KEY NOT NULL,
    host_species_id INTEGER,
    gall_species_id INTEGER,
    FOREIGN KEY(host_species_id) REFERENCES species(id),
    FOREIGN KEY(gall_species_id) REFERENCES species(id)
);

CREATE TABLE source(
    id INTEGER PRIMARY KEY NOT NULL,
    title TEXT UNIQUE NOT NULL , 
    author TEXT,
    pubyear TEXT,
    link TEXT,
    citation TEXT
);

CREATE TABLE speciessource(
    id INTEGER PRIMARY KEY NOT NULL,
    species_id INTEGER,
    source_id INTEGER,
    FOREIGN KEY(species_id) REFERENCES species(id),
    FOREIGN KEY(source_id) REFERENCES source(id)
);

-- This is all static data that is not curated outside of this system.
INSERT INTO taxontype VALUES('gall', 'an abnormal outgrowth of plant tissue usually due to insect or mite parasites or fungi');

INSERT INTO location VALUES(NULL, 'bud', '');
INSERT INTO location VALUES(NULL, 'petiole', '');
INSERT INTO location VALUES(NULL, 'root', '');
INSERT INTO location VALUES(NULL, 'upper leaf', '');
INSERT INTO location VALUES(NULL, 'lower leaf', '');
INSERT INTO location VALUES(NULL, 'leaf midrib', '');
INSERT INTO location VALUES(NULL, 'on leaf veins', '');
INSERT INTO location VALUES(NULL, 'between leaf veins', '');
INSERT INTO location VALUES(NULL, 'at leaf vein angles', '');
INSERT INTO location VALUES(NULL, 'flower', '');
INSERT INTO location VALUES(NULL, 'fruit', '');

INSERT INTO walls VALUES(NULL, 'thin', '');
INSERT INTO walls VALUES(NULL, 'thick', '');
INSERT INTO walls VALUES(NULL, 'broken', '');
INSERT INTO walls VALUES(NULL, 'false chamber', '');

INSERT INTO cells VALUES(NULL, 'single', '');
INSERT INTO cells VALUES(NULL, 'cluster', '');
INSERT INTO cells VALUES(NULL, 'scattered', '');
INSERT INTO cells VALUES(NULL, '2-10', '');

INSERT INTO alignment VALUES(NULL, 'erect', '');
INSERT INTO alignment VALUES(NULL, 'drooping', '');
INSERT INTO alignment VALUES(NULL, 'supine', '');
INSERT INTO alignment VALUES(NULL, 'integral', '');

INSERT INTO color VALUES(NULL, 'brown');
INSERT INTO color VALUES(NULL, 'gray');
INSERT INTO color VALUES(NULL, 'orange');
INSERT INTO color VALUES(NULL, 'pink');
INSERT INTO color VALUES(NULL, 'red');
INSERT INTO color VALUES(NULL, 'white');
INSERT INTO color VALUES(NULL, 'yellow');

INSERT INTO texture VALUES(NULL, 'felt', '');
INSERT INTO texture VALUES(NULL, 'pubescent', '');
INSERT INTO texture VALUES(NULL, 'stiff', '');
INSERT INTO texture VALUES(NULL, 'wooly', '');
INSERT INTO texture VALUES(NULL, 'sticky', '');
INSERT INTO texture VALUES(NULL, 'bumpy', '');
INSERT INTO texture VALUES(NULL, 'waxy', '');
INSERT INTO texture VALUES(NULL, 'areola', '');
INSERT INTO texture VALUES(NULL, 'glaucous', '');
INSERT INTO texture VALUES(NULL, 'hairy', '');
INSERT INTO texture VALUES(NULL, 'hairless', '');
INSERT INTO texture VALUES(NULL, 'resinous dots', '');

INSERT INTO shape VALUES(NULL, 'compact', '');
INSERT INTO shape VALUES(NULL, 'conical', '');
INSERT INTO shape VALUES(NULL, 'globular', '');
INSERT INTO shape VALUES(NULL, 'linear', '');
INSERT INTO shape VALUES(NULL, 'sphere', '');
INSERT INTO shape VALUES(NULL, 'tuft', '');


-- Down
-- DROP TABLE gallsource;
-- DROP TABLE source;
-- DROP TABLE gallhost;
-- DROP TABLE host;
-- DROP TABLE gall;
-- DROP TABLE location;