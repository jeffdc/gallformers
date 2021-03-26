-- Up

PRAGMA foreign_keys=OFF;

-- add the the unknown family and genus
INSERT INTO taxonomy (id, name, description, type) VALUES (NULL, 'Unknown', 'Unknown', 'family');
INSERT INTO taxonomy (id, name, description, type) VALUES (NULL, 'Unknown', 'Unknown', 'genus');

-- port any existing "undescribed" over to unknown


PRAGMA foreign_keys=ON;

--------------------------------------------------------------
-- Down
PRAGMA foreign_keys=OFF;


PRAGMA foreign_keys=ON;
