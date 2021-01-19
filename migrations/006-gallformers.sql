-- Up

PRAGMA foreign_keys=OFF;

-- everything in here is to add cascade delete support since Prisma is useless when it comes to this.
-- speciessource - here we are also adding a new column, externallink
CREATE TABLE speciessource__ (
    id           INTEGER PRIMARY KEY
                         NOT NULL,
    species_id   INTEGER NOT NULL,
    source_id    INTEGER NOT NULL,
    description  TEXT    DEFAULT '',
    useasdefault INTEGER NOT NULL
                         DEFAULT 0,
    externallink TEXT    DEFAULT '',
    FOREIGN KEY (
        species_id
    )
    REFERENCES species (id) ON DELETE CASCADE,
    FOREIGN KEY (
        source_id
    )
    REFERENCES source (id) ON DELETE CASCADE
);
INSERT INTO speciessource__ (id, species_id, source_id, description)
    SELECT id, species_id, source_id, description 
    FROM speciessource;
DROP TABLE speciessource;
ALTER TABLE speciessource__ RENAME TO speciessource;

-- gall - already has it
-- galllocation - already has it
-- galltexture - already has it
-- host - already has it

PRAGMA foreign_keys=ON;

--------------------------------------------------------------
-- Down
PRAGMA foreign_keys=OFF;


PRAGMA foreign_keys=ON;
