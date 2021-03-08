-- Up
BEGIN TRANSACTION;
PRAGMA foreign_keys=OFF;

-- major schema changes to handle the following:
-- 1) Data Quality/Completeness
-- 2) More robust species aliasing
--    a) Mapping a species to source by an aliased name
--    b) undescribed, deprecated, etc.
-- 3) more complete taxonomy support (sections, genus and family as part of taxonomy)
-- 4) allowing more than one gall to be associated with a singel species (sexual/asexual generations)

-- new tables for alias support
CREATE TABLE alias (
    id       INTEGER PRIMARY KEY NOT NULL,
    name     TEXT NOT NULL,
    type     TEXT NOT NULL CHECK (type = 'common' OR type = 'scientific'),
    description TEXT NOT NULL DEFAULT ''
);

CREATE TABLE aliasspecies (
    species_id  INTEGER,
    alias_id    INTEGER,
    FOREIGN KEY (species_id) REFERENCES species (id) ON DELETE CASCADE,
    FOREIGN KEY (alias_id) REFERENCES alias (id) ON DELETE CASCADE,
    PRIMARY KEY(species_id, alias_id)

);

-- table mods for alias support
CREATE TABLE speciessource__ (
    id           INTEGER PRIMARY KEY
                         NOT NULL,
    species_id   INTEGER NOT NULL,
    source_id    INTEGER NOT NULL,
    description  TEXT    DEFAULT '',
    useasdefault INTEGER NOT NULL
                         DEFAULT 0,
    externallink TEXT    DEFAULT '',
    -- new field
    alias_id     INTEGER, -- not required
    FOREIGN KEY (
        species_id
    )
    REFERENCES species (id) ON DELETE CASCADE,
    FOREIGN KEY (
        source_id
    )
    REFERENCES source (id) ON DELETE CASCADE,
    -- new field
    FOREIGN KEY (
        alias_id
    )
    REFERENCES alias (id)
);
INSERT INTO speciessource__ (id, species_id, source_id, description, useasdefault, externallink, alias_id)
    SELECT id, species_id, source_id, description, useasdefault, externallink, NULL 
    FROM speciessource;
DROP TABLE speciessource;
ALTER TABLE speciessource__ RENAME TO speciessource;

--------------------------------------------------------
-- migrate old species alias/common name data
-- extract the commonnames and add them to the new table
INSERT INTO alias (
                      id,
                      name,
                      type
                  )
              WITH RECURSIVE split (
                      species_id,
                      name,
                      rest
                  )
                  AS (
                      SELECT id,
                             '',
                             commonnames || ','
                        FROM species
                       WHERE commonnames IS NOT NULL AND 
                             commonnames != ''
                      UNION ALL
                      SELECT species_id,
                             substr(rest, 0, instr(rest, ',') ),
                             substr(rest, instr(rest, ',') + 1) 
                        FROM split
                       WHERE rest <> ''
                  )
                  SELECT DISTINCT NULL,
                         TRIM(name),
                         'common'
                    FROM split
                   WHERE name <> ''
                   ORDER BY species_id,
                            name;

-- now add the relationships between the commonnames (now as aliases) and the species
INSERT INTO aliasspecies (
                             species_id,
                             alias_id
                         )
                     WITH RECURSIVE split (
                             species_id,
                             name,
                             rest
                         )
                         AS (
                             SELECT id,
                                    '',
                                    commonnames || ','
                               FROM species
                              WHERE commonnames IS NOT NULL AND 
                                    commonnames != ''
                             UNION ALL
                             SELECT species_id,
                                    substr(rest, 0, instr(rest, ',') ),
                                    substr(rest, instr(rest, ',') + 1) 
                               FROM split
                              WHERE rest <> ''
                         )
                         SELECT species_id,
                                alias.id as alias_id
                           FROM split
                           INNER JOIN alias ON alias.name = TRIM(split.name)
                          WHERE split.name <> ''
                          ORDER BY species_id,
                                   split.name;


-- extract the synonyms (scientific) and add them to the new table
INSERT INTO alias (
                      id,
                      name,
                      type
                  )
              WITH RECURSIVE split (
                      species_id,
                      name,
                      rest
                  )
                  AS (
                      SELECT id,
                             '',
                             synonyms || ','
                        FROM species
                       WHERE synonyms IS NOT NULL AND 
                             synonyms != ''
                      UNION ALL
                      SELECT species_id,
                             substr(rest, 0, instr(rest, ',') ),
                             substr(rest, instr(rest, ',') + 1) 
                        FROM split
                       WHERE rest <> ''
                  )
                  SELECT DISTINCT NULL,
                         TRIM(name),
                         'scientific'
                    FROM split
                   WHERE name <> ''
                   ORDER BY species_id,
                            name;

-- now add the relationships between the synonyms (now as aliases) and the species
INSERT INTO aliasspecies (
                             species_id,
                             alias_id
                         )
                     WITH RECURSIVE split (
                             species_id,
                             name,
                             rest
                         )
                         AS (
                             SELECT id,
                                    '',
                                    synonyms || ','
                               FROM species
                              WHERE synonyms IS NOT NULL AND 
                                    synonyms != ''
                             UNION ALL
                             SELECT species_id,
                                    substr(rest, 0, instr(rest, ',') ),
                                    substr(rest, instr(rest, ',') + 1) 
                               FROM split
                              WHERE rest <> ''
                         )
                         SELECT species_id,
                                alias.id as alias_id
                           FROM split
                           INNER JOIN alias ON alias.name = TRIM(split.name)
                          WHERE split.name <> ''
                          ORDER BY species_id,
                                   split.name;


---------------------------------------------------------------------------------
-- Changes for taxonomy
-- rename the family table to taxonomy and add new columns
-- change all of the exisiting data to be family (since it all came from that table)
CREATE TABLE taxonomy (
    id          INTEGER PRIMARY KEY
                        NOT NULL,
    name        TEXT    NOT NULL,
    description TEXT DEFAULT '',
    type        TEXT    NOT NULL CHECK (type = 'family' OR type = 'genus' OR type='section'),
    parent_id   INTEGER DEFAULT NULL,
    FOREIGN KEY (parent_id) REFERENCES taxonomy (id)
);
-- families have no parent so we will use the default, null, value for the parent
INSERT INTO taxonomy (id, name, description, type) 
    SELECT id, name, description, 'family' FROM family;
DROP TABLE family;

-- add new tables for taxonomy
CREATE TABLE taxonomyalias (
    taxonomy_id  INTEGER,
    alias_id    INTEGER,
    FOREIGN KEY (taxonomy_id) REFERENCES taxonomy (id) ON DELETE CASCADE,
    FOREIGN KEY (alias_id) REFERENCES alias (id) ON DELETE CASCADE,
    PRIMARY KEY(taxonomy_id, alias_id)
);

CREATE TABLE speciestaxonomy (
    species_id   INTEGER NOT NULL,
    taxonomy_id  INTEGER NOT NULL,
    FOREIGN KEY (species_id) REFERENCES species (id) ON DELETE CASCADE,
    FOREIGN KEY (taxonomy_id) REFERENCES taxonomy (id) ON DELETE CASCADE,
    PRIMARY KEY(species_id, taxonomy_id)
);

CREATE TABLE taxonomytaxonomy (
    taxonomy_id  INTEGER NOT NULL,
    child_id  INTEGER NOT NULL,
    FOREIGN KEY (taxonomy_id) REFERENCES taxonomy (id) ON DELETE CASCADE,
    FOREIGN KEY (child_id) REFERENCES taxonomy (id) ON DELETE CASCADE,
    PRIMARY KEY(taxonomy_id, child_id)
);

-- migrate genus data to new taxonomy: 
-- 1) insert genus records
INSERT INTO taxonomy (id, name, type, parent_id)
    SELECT DISTINCT NULL, genus, 'genus', family_id FROM species;
-- 2) map to species
INSERT INTO speciestaxonomy (species_id, taxonomy_id)
    SELECT species.id, taxonomy.id 
    FROM species 
    INNER JOIN taxonomy ON taxonomy.name = species.genus;

-- create parent-child relationships for new taxonomy
-- migrate old family to species relationships to genus-family 
INSERT INTO taxonomytaxonomy (taxonomy_id, child_id)
    SELECT DISTINCT family_id, taxonomy.id
    FROM species INNER JOIN taxonomy ON species.genus = taxonomy.name;
    

-- for the sake of having some data we will add the Section mappings for Quercus
-- later an admin UI will be created to maintain these and add new one etc.
INSERT INTO taxonomy (id, name, type, parent_id) 
    VALUES (NULL, 'Quercus', 'section', (SELECT id from taxonomy WHERE name = 'Quercus' AND type = 'genus'));

INSERT INTO alias (id, name, type) 
    SELECT id, 'White Oaks', 'common' 
    FROM taxonomy 
    WHERE name = 'Quercus' AND taxonomy.type='section';

INSERT INTO taxonomyalias (taxonomy_id, alias_id)
    SELECT (SELECT id from taxonomy WHERE name = 'Quercus' and type='section'),
           (SELECT id from alias WHERE name = 'White Oaks');

INSERT INTO speciestaxonomy (species_id, taxonomy_id) 
    WITH species_list(spid) AS
        (VALUES (296),(297),(298),(299),(300),(302),(306),(310),(313),(322),(326),
                (327),(329),(331),(332),(333),(336),(340),(341),(343),(344),(345),
                (348),(349),(352)
        ) SELECT spid, taxid
        FROM species_list
        CROSS JOIN (SELECT id as taxid FROM taxonomy WHERE name = 'Quercus' AND type = 'section');

INSERT INTO taxonomy (id, name, type, parent_id) 
    VALUES (NULL, 'Lobatae', 'section', (SELECT id from taxonomy WHERE name = 'Quercus' AND type = 'genus'));

INSERT INTO alias (id, name, type) 
    SELECT id, 'Red Oaks', 'common' FROM taxonomy WHERE name = 'Lobatae' AND type ='section';

INSERT INTO taxonomyalias (taxonomy_id, alias_id)
    SELECT (SELECT id from taxonomy WHERE name = 'Lobatae' and type='section'),
           (SELECT id from alias WHERE name = 'Red Oaks');

INSERT INTO speciestaxonomy (species_id, taxonomy_id) 
    WITH species_list(spid) AS
        (VALUES (295),(305),(307),(308),(314),(315),(317),(319),(320),(323),(324),
                (325),(330),(334),(335),(337),(338),(339),(343),(346),(347),(351),
                (355),(357)
        ) SELECT spid, taxid
        FROM species_list
        CROSS JOIN (SELECT id as taxid FROM taxonomy WHERE name = 'Lobatae' AND type = 'section');


INSERT INTO taxonomy (id, name, type, parent_id) 
    VALUES (NULL, 'Virentes', 'section', (SELECT id from taxonomy WHERE name = 'Quercus' AND type = 'genus'));

INSERT INTO alias (id, name, type) 
    SELECT id, 'Live Oaks', 'common' FROM taxonomy WHERE name = 'Virentes' AND type = 'section';

INSERT INTO taxonomyalias (taxonomy_id, alias_id)
    SELECT (SELECT id from taxonomy WHERE name = 'Virentes' and type='section'),
           (SELECT id from alias WHERE name = 'Live Oaks');

INSERT INTO speciestaxonomy (species_id, taxonomy_id) 
    WITH species_list(spid) AS
        (VALUES (309),(311),(356))
        SELECT spid, taxid
        FROM species_list
        CROSS JOIN (SELECT id as taxid FROM taxonomy WHERE name = 'Virentes' AND type = 'section');

---------------------------------------------------------------------------------------
-- Changes for many galls to species
-- new table
CREATE TABLE gallspecies (
    species_id INTEGER,
    gall_id    INTEGER,
    FOREIGN KEY (species_id) REFERENCES species (id) ON DELETE CASCADE,
    FOREIGN KEY (gall_id) REFERENCES gall (id) ON DELETE CASCADE,
    PRIMARY KEY(species_id, gall_id)
);

-- migrate exisiting 1-1 species-gall mappings into new structure
INSERT INTO gallspecies (species_id, gall_id)
    SELECT species_id, id FROM gall;

-- Now modify old tables:
-- update gall table to remove species_id
CREATE TABLE gall__ (
    id         INTEGER PRIMARY KEY
                       NOT NULL,
    taxoncode  TEXT    NOT NULL
                       CHECK (taxoncode = 'gall'),
    detachable INTEGER,
    FOREIGN KEY (
        taxonCode
    )
    REFERENCES taxontype (taxonCode) 
);
INSERT INTO gall__ (id, taxoncode, detachable)
    SELECT id, taxoncode, detachable FROM gall;
DROP TABLE gall;
ALTER TABLE gall__ RENAME TO gall;

-------------------------------------------------------------------------------------
-- update species table to:
-- * remove old alias fields
-- * add new field for data completeness
-- * remove genus field
-- * remove family_id
-- * remove gallid
CREATE TABLE species__ (
    id           INTEGER PRIMARY KEY
                         NOT NULL,
    taxoncode    TEXT,
    name         TEXT    UNIQUE
                         NOT NULL,
    datacomplete BOOLEAN DEFAULT 0,
    abundance_id INTEGER,
    FOREIGN KEY (
        taxoncode
    )
    REFERENCES taxontype (taxonCode),
    FOREIGN KEY (
        abundance_id
    )
    REFERENCES abundance (id)
);
INSERT INTO species__ (id, taxoncode, name, abundance_id)
    SELECT id, taxoncode, name, abundance_id FROM species;
DROP TABLE species;
ALTER TABLE species__ RENAME TO species;


PRAGMA foreign_keys=ON;
COMMIT;

-- Down
PRAGMA foreign_keys=OFF;
-- Nothing to do, too complex to roll back 
PRAGMA foreign_keys=ON;
