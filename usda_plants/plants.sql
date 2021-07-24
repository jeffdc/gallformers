--
-- File generated with SQLiteStudio v3.3.3 on Fri Jul 9 10:57:13 2021
--
-- Text encoding used: UTF-8
--
PRAGMA foreign_keys = off;
BEGIN TRANSACTION;

CREATE TABLE alias (
    id   INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT    NOT NULL UNIQUE
);

CREATE TABLE plant (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    rawname       TEXT    NOT NULL UNIQUE,
    symbol        TEXT    NOT NULL,
    symbolsynonym TEXT    NOT NULL DEFAULT "",
    family        TEXT    NOT NULL,
    genus         TEXT    NOT NULL,
    specific      TEXT    NOT NULL,
    type          TEXT    NOT NULL CHECK (type IN ("ssp.", "var.", "sp.", "x") ),
    sspvar        TEXT    NOT NULL DEFAULT "",
    hybridpair    TEXT    NOT NULL DEFAULT "",
    author        TEXT    NOT NULL,
    secondauthor  TEXT    NOT NULL DEFAULT ""
);

CREATE TABLE plantalias (
    plant_id  INTEGER REFERENCES plant (id) ON DELETE CASCADE,
    alias_id  INTEGER REFERENCES alias (id) ON DELETE CASCADE,
    type      TEXT NOT NULL CHECK (type IN ("common", "orth. var.") )
);

CREATE TABLE plantregion (
    plant_id   INTEGER REFERENCES plant (id) ON DELETE CASCADE
               NOT NULL,
    region_id  INTEGER REFERENCES region (id) ON DELETE CASCADE
               NOT NULL
);

CREATE TABLE region (
    id   INTEGER PRIMARY KEY AUTOINCREMENT
                 NOT NULL,
    name TEXT    NOT NULL,
    code TEXT    NOT NULL
);


COMMIT TRANSACTION;
PRAGMA foreign_keys = on;
