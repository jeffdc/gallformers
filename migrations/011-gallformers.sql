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

-- port any existing "undescribed" over to unknown


PRAGMA foreign_keys=ON;

--------------------------------------------------------------
-- Down
PRAGMA foreign_keys=OFF;


PRAGMA foreign_keys=ON;
