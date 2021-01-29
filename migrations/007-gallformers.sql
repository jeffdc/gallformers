-- Up

PRAGMA foreign_keys=OFF;

-- adding support for image relationships to species-source mappings
CREATE TABLE image__ (
    id          INTEGER PRIMARY KEY
                        NOT NULL,
    species_id  INTEGER NOT NULL,
    source_id   INTEGER,
    path        TEXT    UNIQUE
                        NOT NULL,
    [default]   BOOLEAN DEFAULT FALSE,
    creator     TEXT,
    attribution TEXT,
    sourcelink  TEXT,
    license     TEXT,
    uploader    TEXT,
    FOREIGN KEY (
        species_id
    )
    REFERENCES species (id) ON DELETE CASCADE,
    FOREIGN KEY (
        source_id
    )
    REFERENCES source (id) ON DELETE CASCADE
);

INSERT INTO image__ (id, species_id, path, [default], creator, attribution, sourcelink, license, uploader, species_id)
    SELECT id, species_id, path, [default], creator, attribution, source, license, uploader, species_id 
    FROM image;
DROP TABLE image;
ALTER TABLE image__ RENAME TO image;

PRAGMA foreign_keys=ON;

--------------------------------------------------------------
-- Down
PRAGMA foreign_keys=OFF;


PRAGMA foreign_keys=ON;
