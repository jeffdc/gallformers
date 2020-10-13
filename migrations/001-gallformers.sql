-- Up
CREATE TABLE galllocation(
    loc_id INTEGER PRIMARY KEY NOT NULL,
    loc TEXT
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
    detachable INTEGER,
    texture TEXT,
    alignment TEXT,
    walls TEXT,
    loc_id INTEGER,
    FOREIGN KEY(species_id) REFERENCES species(species_id)
    FOREIGN KEY(taxonCode) REFERENCES taxontype(taxonCode)
    FOREIGN KEY(loc_id) REFERENCES galllocation(loc_id)
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
INSERT INTO galllocation VALUES(NULL, 'stem');
INSERT INTO galllocation VALUES(NULL, 'root');
INSERT INTO galllocation VALUES(NULL, 'upper leaf - on veins');
INSERT INTO galllocation VALUES(NULL, 'upper leaf - between veins');
INSERT INTO galllocation VALUES(NULL, 'upper leaf - vein angles');
INSERT INTO galllocation VALUES(NULL, 'lower leaf - on veins');
INSERT INTO galllocation VALUES(NULL, 'lower leaf - between veins');
INSERT INTO galllocation VALUES(NULL, 'lower leaf - vein angles');

-- INSERT INTO "gall" VALUES(NULL, 'Andricus apiarium', NULL, 'Andricus', 'Cynipidae', 
--                            'Solitary, sessile, on underside of leaf close to edge in October, shaped like an old-fashioned straw beehive, white or pinkish, measuring up to 4.6 mm broad by 4.0 mm high. Inside is a large cavity with a transverse larval cell at very base. During the winter on the ground the outer fleshy layer shrivels and the gall becomes more cylindrical.',
--                            '1', 'hairless', 'erect', 'thick', 'uncommon', (SELECT id FROM galllocation WHERE loc = 'lower leaf - between veins'));
                           
-- INSERT INTO "host" VALUES(NULL, 'Quercus alba', 'White Oak', 'Quercus', 'Fagaceae');
-- INSERT INTO "host" VALUES(NULL, 'Quercus phellos', 'Willow Oak', 'Quercus', 'Fagaceae');
-- INSERT INTO "host" VALUES(NULL, 'Quercus stellata', 'Post Oak', 'Quercus', 'Fagaceae');

-- INSERT INTO "gallhost" VALUES((SELECT id FROM host WHERE name = 'Quercus alba'), 
--                               (SELECT id from gall WHERE name = 'Andricus apiarium')
--                              );

-- INSERT INTO "source" VALUES(NULL, 'New American Cynipid Wasps From Galls', 'Weld, L.H.', '1952-01-01 00:00;00.000', 
--                              'https://www.biodiversitylibrary.org/page/15672479#page/372/mode/1up',
--                              'Weld, Lewis H. "New American cynipid wasps from galls." Proceedings of the United States National Museum (1952).');
-- INSERT INTO "gallsource" VALUES((SELECT id from gall WHERE name = 'Andricus apiarium'),
--                                 (SELECT id from source WHERE title = 'New American Cynipid Wasps From Galls')
--                                );

-- Down
-- DROP TABLE gallsource;
-- DROP TABLE source;
-- DROP TABLE gallhost;
-- DROP TABLE host;
-- DROP TABLE gall;
-- DROP TABLE galllocation;