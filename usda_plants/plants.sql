--
-- File generated with SQLiteStudio v3.3.3 on Fri Jul 9 10:57:13 2021
--
-- Text encoding used: UTF-8
--
PRAGMA foreign_keys = off;
BEGIN TRANSACTION;

-- Table: commonname
CREATE TABLE commonname (
    id   INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT    NOT NULL
                 UNIQUE
);


-- Table: plant
CREATE TABLE plant (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    name          TEXT    NOT NULL
                          UNIQUE,
    symbol        TEXT    NOT NULL,
    symbolsynonym TEXT,
    family        TEXT    NOT NULL
);


-- Table: plantcommonname
CREATE TABLE plantcommonname (
    plant_id       INTEGER REFERENCES plant (id) ON DELETE CASCADE,
    commonname_id  INTEGER REFERENCES commonname (id) ON DELETE CASCADE
);


-- Table: plantregion
CREATE TABLE plantregion (
    plant_id   INTEGER REFERENCES plant (id) ON DELETE CASCADE
               NOT NULL,
    region_id  INTEGER REFERENCES region (id) ON DELETE CASCADE
               NOT NULL
);


-- Table: region
CREATE TABLE region (
    id   INTEGER PRIMARY KEY AUTOINCREMENT
                 NOT NULL,
    name TEXT    NOT NULL,
    code TEXT    NOT NULL
);


COMMIT TRANSACTION;
PRAGMA foreign_keys = on;
