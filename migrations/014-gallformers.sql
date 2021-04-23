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

PRAGMA foreign_keys=ON;

--------------------------------------------------------------
-- Down
PRAGMA foreign_keys=OFF;


PRAGMA foreign_keys=ON;
