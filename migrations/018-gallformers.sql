-- Up

PRAGMA foreign_keys=OFF;

-- change Canada's code to CAN from CA
UPDATE place SET code = 'CAN' WHERE name = 'Canada';

-- find any speciesplace records that are mapped to Canada and delete them
DELETE FROM speciesplace WHERE place_id = (SELECT id FROM place WHERE name = 'Canada');

PRAGMA foreign_keys=ON;

--------------------------------------------------------------
-- Down
PRAGMA foreign_keys=OFF;


PRAGMA foreign_keys=ON;
