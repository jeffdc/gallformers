-- Up

PRAGMA foreign_keys=OFF;

-- Simple changes adding gall descriptors per #115
INSERT INTO texture (id, texture, description) VALUES (NULL, 'leafy', '');
INSERT INTO texture (id, texture, description) VALUES (NULL, 'mottled', '');
INSERT INTO texture (id, texture, description) VALUES (NULL, 'succulent', '');
INSERT INTO texture (id, texture, description) VALUES (NULL, 'spiky/thorny', '');
INSERT INTO cells (id, cells, description) VALUES (NULL, 'free-rolling', '');
INSERT INTO walls (id, walls, description) VALUES (NULL, 'radiating-fibers', '');
INSERT INTO walls (id, walls, description) VALUES (NULL, 'spongy', '');

-- #117 clean up duplicate genera

-- a temp table that holds all of the good genera that we want to keep and whose ids we will
-- use to replace the duplicate genera
CREATE TEMP TABLE tax (
    id        INTEGER,
    name      TEXT
);

INSERT INTO [temp].tax (
                           id,
                           name
                       )
                       SELECT id,
                              name
                         FROM taxonomy
                         WHERE type = 'genus'
                        GROUP BY name,
                                 parent_id
                       HAVING count( * ) > 1;

-- a temp table that holds all of the duplicated taxonomy records with the proper ID, i.e., the one from the other temp table
CREATE TEMP TABLE taxdup (
    id        INTEGER,
    name      TEXT,
    proper_id INTEGER
);

INSERT INTO [temp].taxdup (
                              id,
                              name,
                              proper_id
                          )
                          SELECT a.id,
                                 a.name,
                                 b.id
                            FROM taxonomy as a
                            JOIN [temp].tax as b ON a.name = b.name
                           WHERE a.id NOT IN (
                                     SELECT id
                                       FROM [temp].tax
                                 )
AND 
                                 a.name IN (
                                     SELECT name
                                       FROM [temp].tax
                                 )
                                 order by a.name;

-- update all of the records in the speciestaxonomy table that are duplicates with the proper id
-- we use an INGORE here as there are some duplicates relating to the Quercus genus, see next step.
UPDATE OR IGNORE speciestaxonomy
   SET taxonomy_id = (
           SELECT proper_id
             FROM [temp].taxdup
            WHERE id = taxonomy_id
       )
 WHERE taxonomy_id IN (
    SELECT id
      FROM [temp].taxdup
);


-- if there are any leftover that need fixing they are duplicates and we will delete them
-- this was due to an error in the way Sections where handled and only affected some of the Quercus entries
-- this step is not strictly needed since the next step will cascade delete these but I wanted it to be very
-- clear what is happening
DELETE FROM speciestaxonomy
      WHERE taxonomy_id IN (
    SELECT id
      FROM [temp].taxdup
);

-- finally delete the bad records from the taxonomy table
DELETE FROM taxonomy
      WHERE id IN (
    SELECT id
      FROM [temp].taxdup
);

DROP TABLE [temp].tax;
DROP TABLE [temp].taxdup;

-- also had some bad data where Families were related to species and genera where NOT related to families
-- delete any species -> family mappings as these are invalid
DELETE FROM speciestaxonomy
WHERE EXISTS (
    SELECT species_id,
           taxonomy_id
      FROM speciestaxonomy AS st2
           INNER JOIN
           taxonomy AS t ON t.id = st2.taxonomy_id
     WHERE t.type = 'family' AND speciestaxonomy.taxonomy_id = t.id
);

CREATE TEMP TABLE bad (
    id        INTEGER,
    name      TEXT,
    genid     INTEGER,
    type      TEXT,
    parent_id  INTEGER
);

-- find species mapped to genera that are not mapped to a family
INSERT INTO [temp].bad (
                           id,
                           name,
                           genid,
                           type,
                           parent_id
                       )
                       SELECT s.id,
                              s.name,
                              spt.taxonomy_id,
                              tax.type,
                              tax.parent_id
                         FROM species AS s
                              INNER JOIN
                              speciestaxonomy AS spt ON s.id = spt.species_id
                              INNER JOIN taxonomy as tax ON spt.taxonomy_id = tax.id
                        WHERE s.id NOT IN (
                                  SELECT s.id
                                    FROM species AS s
                                         INNER JOIN
                                         speciestaxonomy AS st ON s.id = st.species_id
                                         INNER JOIN
                                         taxonomy AS gt ON st.taxonomy_id = gt.id
                                         INNER JOIN
                                         taxonomytaxonomy AS tt ON gt.id = tt.child_id
                                         INNER JOIN
                                         taxonomy AS pt ON tt.taxonomy_id = pt.id
                              );



-- assign an existing family to the bad records
INSERT OR IGNORE INTO taxonomytaxonomy (
                                 taxonomy_id,
                                 child_id
                             )
                             SELECT parent_id,
                                    genid
                               FROM [temp].bad;

DROP TABLE [temp].bad;

VACUUM;

PRAGMA foreign_keys=ON;

--------------------------------------------------------------
-- Down
PRAGMA foreign_keys=OFF;


PRAGMA foreign_keys=ON;
