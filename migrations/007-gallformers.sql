-- Up

PRAGMA foreign_keys=OFF;

-- adding support for image relationships to species-source mappings
-- adding licenselink and lastchangedby fields
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
    licenselink TEXT,
    uploader    TEXT,
    lastchangedby TEXT,
    FOREIGN KEY (
        species_id
    )
    REFERENCES species (id) ON DELETE CASCADE,
    FOREIGN KEY (
        source_id
    )
    REFERENCES source (id) ON DELETE CASCADE
);

INSERT INTO image__ (id, species_id, path, [default], creator, attribution, sourcelink, license, uploader, lastchangedby, species_id)
    SELECT id, species_id, path, [default], creator, attribution, source, license, uploader, uploader, species_id 
    FROM image;
DROP TABLE image;
ALTER TABLE image__ RENAME TO image;

PRAGMA foreign_keys=ON;

--------------------------------------------------------------
-- Down
PRAGMA foreign_keys=OFF;


PRAGMA foreign_keys=ON;
