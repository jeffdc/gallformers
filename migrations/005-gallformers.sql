-- Up

PRAGMA foreign_keys=OFF;

CREATE TABLE image(
    id INTEGER PRIMARY KEY NOT NULL,
    path TEXT UNIQUE NOT NULL,
    creator TEXT,
    attribution TEXT,
    source TEXT,
    license TEXT,
    uploader TEXT
);

CREATE TABLE speciesimage(
    id INTEGER PRIMARY KEY NOT NULL,
    species_id INTEGER NOT NULL,
    image_id INTEGER NOT NULL,
    [default]  BOOLEAN DEFAULT FALSE,
    FOREIGN KEY(species_id) REFERENCES species(id),
    FOREIGN KEY(image_id) REFERENCES image(id)
);

PRAGMA foreign_keys=ON;

--------------------------------------------------------------
-- Down
PRAGMA foreign_keys=OFF;

DROP TABLE speciesimage;
DROP TABLE image;

PRAGMA foreign_keys=ON;
