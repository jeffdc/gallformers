-- Up

PRAGMA foreign_keys=OFF;

-- there is at least one orphaned Genus record that needs to be deleted
DELETE FROM taxonomy
      WHERE id IN (
    SELECT id
      FROM taxonomy
     WHERE type = 'genus' AND 
           id NOT IN (
               SELECT taxonomy_id
                 FROM speciestaxonomy
           )
);

DELETE FROM taxonomytaxonomy
  WHERE child_id NOT IN (
    SELECT id FROM taxonomy
  );


PRAGMA foreign_keys=ON;

--------------------------------------------------------------
-- Down
PRAGMA foreign_keys=OFF;


PRAGMA foreign_keys=ON;
