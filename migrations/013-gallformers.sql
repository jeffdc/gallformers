
-- Up

PRAGMA foreign_keys=OFF;

-- still have some orphaned data leftover from the genus kerfluffle
DELETE FROM taxonomytaxonomy
      WHERE child_id IN (
    SELECT child_id
      FROM taxonomytaxonomy AS tt
     WHERE tt.child_id NOT IN (
               SELECT id
                 FROM taxonomy
           )
);

-- #133 - add season to gall
CREATE TABLE season (
    id INTEGER PRIMARY KEY NOT NULL,
    season TEXT UNIQUE NOT NULL
);
CREATE TABLE gallseason (
    id       INTEGER PRIMARY KEY NOT NULL,
    gall_id  INTEGER,
    season_id INTEGER,
    FOREIGN KEY (gall_id) REFERENCES gall (id) ON DELETE CASCADE,
    FOREIGN KEY (season_id) REFERENCES season (id) ON DELETE CASCADE 
);
INSERT INTO season (id, season) VALUES (NULL, 'Spring');
INSERT INTO season (id, season) VALUES (NULL, 'Summer');
INSERT INTO season (id, season) VALUES (NULL, 'Fall');
INSERT INTO season (id, season) VALUES (NULL, 'Winter');

-- #107 add complete flag to source
ALTER table source ADD COLUMN datacomplete BOOLEAN DEFAULT 0 NOT NULL;

-- #91 Add License info to Sources
ALTER table source ADD COLUMN license TEXT DEFAULT '' NOT NULL;
ALTER table source ADD COLUMN liceselink TEXT DEFAULT '' NOT NULL;


PRAGMA foreign_keys=ON;

--------------------------------------------------------------
-- Down
PRAGMA foreign_keys=OFF;


PRAGMA foreign_keys=ON;

