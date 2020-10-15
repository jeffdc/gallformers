-- Up

-- These are static tables that hold various constants and what not. While it is tempting to slam them
-- all together into one giant lookup table this leads to other problems.. see: https://www.red-gate.com/simple-talk/sql/database-administration/five-simple-database-design-errors-you-should-avoid/
CREATE TABLE galllocation(
    loc_id INTEGER PRIMARY KEY NOT NULL,
    loc TEXT,
    description TEXT
);

CREATE TALE texture(
    texture_id INTEGER PRIMARY KEY NOT NULL,
    texture text,
    description TEXT
);

CREATE TABLE color(
    color_id INTEGER PRIMARY KEY NOT NULL,
    color text
);

CREATE TABLE walls(
    walls_id INTEGER PRIMARY KEY NOT NULL,
    walls text,
    description TEXT
);

CREATE TABLE cells(
    cells_id INTEGER PRIMARY KEY NOT NULL,
    cells text,
    description TEXT
);

CREATE table shape(
    shape_id INTEGER PRIMARY KEY NOT NULL,
    shape text,
    description TEXT
);

CREATE TABLE abundance(
    adundancecode TEXT PRIMARY KEY NOT NULL,
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

CREATE TABLE species(
    species_id INTEGER PRIMARY KEY NOT NULL,
    taxoncode TEXT,
    name TEXT NOT NULL, -- this is the accepted binomial 'Genus species' name
    synonyms TEXT, -- CSV text
    commonNames TEXT, -- CSV text
    genus TEXT NOT NULL,
    family TEXT NOT NULL,
    description TEXT,
    abundancecode TEXT,
    FOREIGN KEY(taxoncode) REFERENCES taxontype(taxonCode),
    FOREIGN KEY(abundancecode) REFERENCES abundance(abundancecode)
);

CREATE TABLE gall(
    species_id INTEGER NOT NULL,
    taxoncode TEXT NOT NULL CHECK (taxoncode = 'gall'),
    detachable INTEGER, -- boolean: 0 = false; 1 = true, standard sqlite
    texture_id INTEGER,
    alignment_id INTEGER,
    walls_id INTEGER,
    color_id INTEGER,
    shape_id INTEGER,
    loc_id INTEGER,
    FOREIGN KEY(species_id) REFERENCES species(species_id)
    FOREIGN KEY(taxonCode) REFERENCES taxontype(taxonCode)
    FOREIGN KEY(loc_id) REFERENCES galllocation(loc_id)
    FOREIGN KEY(walls_id) REFERENCES walls(walls_id)
    FOREIGN KEY(color_id) REFERENCES color(color_id)
    FOREIGN KEY(loc_id) REFERENCES shape(shape_id)
    FOREIGN KEY(loc_id) REFERENCES alignment(alignment_id)
);

-- a host is just a many-to-many relationship between species
CREATE TABLE host(
    host_species_id INTEGER,
    species_id INTEGER,
    FOREIGN KEY(host_species_id) REFERENCES species(species_id),
    FOREIGN KEY(species_id) REFERENCES species(species_id)
);

CREATE TABLE source(
    source_id INTEGER PRIMARY KEY NOT NULL,
    title TEXT UNIQUE NOT NULL , 
    author TEXT,
    pubyear TEXT,
    link TEXT,
    citation TEXT
);

CREATE TABLE speciessource(
    species_id INTEGER,
    source_id INTEGER,
    FOREIGN KEY(species_id) REFERENCES species(species_id),
    FOREIGN KEY(source_id) REFERENCES source(source_id)
);

-- This is all static data that is not curated outside of this system.
INSERT INTO taxontype VALUES('gall', 'an abnormal outgrowth of plant tissue usually due to insect or mite parasites or fungi');

INSERT INTO galllocation VALUES(NULL, 'bud');
INSERT INTO galllocation VALUES(NULL, 'petiole');
INSERT INTO galllocation VALUES(NULL, 'root');
INSERT INTO galllocation VALUES(NULL, 'upper leaf');
INSERT INTO galllocation VALUES(NULL, 'lower leaf');
INSERT INTO galllocation VALUES(NULL, 'leaf midrib');
INSERT INTO galllocation VALUES(NULL, 'on leaf veins');
INSERT INTO galllocation VALUES(NULL, 'between leaf veins');
INSERT INTO galllocation VALUES(NULL, 'at leaf vein angles');
INSERT INTO galllocation VALUES(NULL, 'flower'); -- is there a generic word to fill in for things like samara, catakin, etc.?
INSERT INTO galllocation VALUES(NULL, 'fruit');

INSERT INTO walls VALUES(NULL, 'thin');
INSERT INTO walls VALUES(NULL, 'thick');
INSERT INTO walls VALUES(NULL, 'broken');
INSERT INTO walls VALUES(NULL, 'false chamber');

INSERT INTO cells VALUES(NULL, 'single');
INSERT INTO cells VALUES(NULL, 'cluster');
INSERT INTO cells VALUES(NULL, 'scattered');
INSERT INTO cells VALUES(NULL, '2-10');

INSERT INTO alignment VALUES(NULL, 'erect');
INSERT INTO alignment VALUES(NULL, 'drooping');
INSERT INTO alignment VALUES(NULL, 'supine');
INSERT INTO alignment VALUES(NULL, 'integral');

INSERT INTO color VALUES(NULL, 'brown');
INSERT INTO color VALUES(NULL, 'gray');
INSERT INTO color VALUES(NULL, 'orange');
INSERT INTO color VALUES(NULL, 'pink');
INSERT INTO color VALUES(NULL, 'red');
INSERT INTO color VALUES(NULL, 'white');
INSERT INTO color VALUES(NULL, 'yellow');

INSERT INTO texture VALUES(NULL, 'felt');
INSERT INTO texture VALUES(NULL, 'pubescent');
INSERT INTO texture VALUES(NULL, 'stiff');
INSERT INTO texture VALUES(NULL, 'wooly');
INSERT INTO texture VALUES(NULL, 'sticky');
INSERT INTO texture VALUES(NULL, 'bumpy');
INSERT INTO texture VALUES(NULL, 'waxy');
INSERT INTO texture VALUES(NULL, 'areola');
INSERT INTO texture VALUES(NULL, 'glaucous');
INSERT INTO texture VALUES(NULL, 'hairy');
INSERT INTO texture VALUES(NULL, 'hairless');
INSERT INTO texture VALUES(NULL, 'resinous dots');

INSERT INTO shape VALUES(NULL, 'compact');
INSERT INTO shape VALUES(NULL, 'conical');
INSERT INTO shape VALUES(NULL, 'globular');
INSERT INTO shape VALUES(NULL, 'linear');
INSERT INTO shape VALUES(NULL, 'sphere');
INSERT INTO shape VALUES(NULL, 'tuft');


-- Down
-- DROP TABLE gallsource;
-- DROP TABLE source;
-- DROP TABLE gallhost;
-- DROP TABLE host;
-- DROP TABLE gall;
-- DROP TABLE galllocation;