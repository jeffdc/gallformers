-- Up

PRAGMA foreign_keys=OFF;

CREATE TABLE image(
    id INTEGER PRIMARY KEY NOT NULL,
    species_id INTEGER NOT NULL,
    path TEXT UNIQUE NOT NULL,
    [default]  BOOLEAN DEFAULT FALSE,
    creator TEXT,
    attribution TEXT,
    source TEXT,
    license TEXT,
    uploader TEXT,
    FOREIGN KEY(species_id) REFERENCES species(id) ON DELETE CASCADE
);

PRAGMA foreign_keys=ON;

--------------------------------------------------------------
-- Down
PRAGMA foreign_keys=OFF;

DROP TABLE image;

PRAGMA foreign_keys=ON;
