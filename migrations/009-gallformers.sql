-- Up

PRAGMA foreign_keys=OFF;

-- change gall properties: cells, walls, color, shape, alignment from single to mult-select

-- new relationship tables
CREATE TABLE gallcolor (
    id       INTEGER PRIMARY KEY NOT NULL,
    gall_id  INTEGER,
    color_id INTEGER,
    FOREIGN KEY (gall_id) REFERENCES gall (id) ON DELETE CASCADE,
    FOREIGN KEY (color_id) REFERENCES color (id) ON DELETE CASCADE 
);

CREATE TABLE gallshape (
    id       INTEGER PRIMARY KEY NOT NULL,
    gall_id  INTEGER,
    shape_id INTEGER,
    FOREIGN KEY (gall_id) REFERENCES gall (id) ON DELETE CASCADE,
    FOREIGN KEY (shape_id) REFERENCES shape (id) ON DELETE CASCADE
);

CREATE TABLE gallcells (
    id       INTEGER PRIMARY KEY NOT NULL,
    gall_id  INTEGER,
    cells_id INTEGER,
    FOREIGN KEY (gall_id) REFERENCES gall (id) ON DELETE CASCADE,
    FOREIGN KEY (cells_id) REFERENCES cells (id) ON DELETE CASCADE
);

CREATE TABLE gallwalls (
    id       INTEGER PRIMARY KEY NOT NULL,
    gall_id  INTEGER,
    walls_id INTEGER,
    FOREIGN KEY (gall_id) REFERENCES gall (id) ON DELETE CASCADE,
    FOREIGN KEY (walls_id) REFERENCES walls (id) ON DELETE CASCADE
);

CREATE TABLE gallalignment (
    id       INTEGER PRIMARY KEY NOT NULL,
    gall_id  INTEGER,
    alignment_id INTEGER,
    FOREIGN KEY (gall_id) REFERENCES gall (id) ON DELETE CASCADE,
    FOREIGN KEY (alignment_id) REFERENCES alignment (id) ON DELETE CASCADE
);

-- migrate data
INSERT INTO gallcolor (id, gall_id, color_id) SELECT NULL, id, color_id FROM gall WHERE color_id IS NOT NULL;
INSERT INTO gallshape (id, gall_id, shape_id) SELECT NULL, id, shape_id FROM gall WHERE shape_id IS NOT NULL;
INSERT INTO gallcells (id, gall_id, cells_id) SELECT NULL, id, cells_id FROM gall WHERE cells_id IS NOT NULL;
INSERT INTO gallwalls (id, gall_id, walls_id) SELECT NULL, id, walls_id FROM gall WHERE walls_id IS NOT NULL;
INSERT INTO gallalignment (id, gall_id, alignment_id) SELECT NULL, id, alignment_id FROM gall WHERE alignment_id IS NOT NULL;

-- drop old columns
CREATE TABLE gall__ (
    id           INTEGER PRIMARY KEY
                         NOT NULL,
    species_id   INTEGER NOT NULL,
    taxoncode    TEXT    NOT NULL
                         CHECK (taxoncode = 'gall'),
    detachable   INTEGER,
    FOREIGN KEY (
        species_id
    )
    REFERENCES species (id) ON DELETE CASCADE,
    FOREIGN KEY (
        taxonCode
    )
    REFERENCES taxontype (taxonCode)
);

INSERT INTO gall__ (id, species_id, taxoncode, detachable)
    SELECT id, species_id, taxoncode, detachable 
    FROM gall;
DROP TABLE gall;
ALTER TABLE gall__ RENAME TO gall;

-- We changed the way we handle detachable so we need to migrate that data as well
-- 1 used to mean detachable was true, now it means 'Detachable' which is 2
UPDATE gall SET detachable = 2 WHERE gall.detachable is 1;
-- 0 used to mean detachable was false, now it means 'Integral' which is 1
UPDATE gall SET detachable = 1 WHERE gall.detachable is 0;
-- NULL used to mean detachable was not set, which now means 'None' which is 0
UPDATE gall SET detachable = 0 WHERE gall.detachable is NULL;
-- there was no notion of 'Both' in the old meaning so we will not set any to 'Both' which is 3

-- specific updates of data that was bogus
UPDATE gall SET detachable = 2 WHERE gall.id IN (53,43,48,39,40,42,71,47,52,45,62,44,73,68,70,50,49,51,55,60);
UPDATE gall SET detachable = 3 WHERE gall.id IN (54,30,41);

PRAGMA foreign_keys=ON;

--------------------------------------------------------------
-- Down
PRAGMA foreign_keys=OFF;


PRAGMA foreign_keys=ON;
