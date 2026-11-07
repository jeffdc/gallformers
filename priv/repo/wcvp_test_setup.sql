-- WCVP test database setup
-- Creates tables and loads fixture data for the wcvp_test database.
-- Run as part of `make test-db`.

DROP TABLE IF EXISTS wcvp_distributions;
DROP TABLE IF EXISTS wcvp_names;
DROP TABLE IF EXISTS meta;

CREATE TABLE wcvp_names (
  plant_name_id TEXT PRIMARY KEY,
  taxon_name TEXT NOT NULL,
  taxon_rank TEXT,
  taxon_status TEXT NOT NULL DEFAULT 'Accepted',
  accepted_plant_name_id TEXT,
  family TEXT NOT NULL,
  genus TEXT NOT NULL,
  species TEXT NOT NULL,
  taxon_authors TEXT,
  powo_id TEXT
);

CREATE TABLE wcvp_distributions (
  plant_locality_id TEXT PRIMARY KEY,
  plant_name_id TEXT NOT NULL,
  area_code_l3 TEXT NOT NULL,
  introduced TEXT NOT NULL DEFAULT '0',
  extinct TEXT NOT NULL DEFAULT '0',
  location_doubtful TEXT NOT NULL DEFAULT '0',
  FOREIGN KEY (plant_name_id) REFERENCES wcvp_names(plant_name_id)
);

CREATE TABLE meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

-- Fixture names (same data as lookup_test.exs setup)
INSERT INTO wcvp_names (plant_name_id, taxon_name, taxon_status, accepted_plant_name_id, family, genus, species, taxon_authors, powo_id) VALUES
  ('100', 'Quercus alba', 'Accepted', '100', 'Fagaceae', 'Quercus', 'alba', 'L.', 'urn:lsid:ipni.org:names:295763-1'),
  ('101', 'Quercus rubra', 'Accepted', '101', 'Fagaceae', 'Quercus', 'rubra', 'L.', 'urn:lsid:ipni.org:names:295776-1'),
  ('102', 'Quercus velutina', 'Accepted', '102', 'Fagaceae', 'Quercus', 'velutina', 'Lam.', NULL),
  ('200', 'Rosa carolina', 'Accepted', '200', 'Rosaceae', 'Rosa', 'carolina', 'L.', 'urn:lsid:ipni.org:names:726498-1'),
  ('300', 'Alnus alnobetula subsp. sinuata', 'Accepted', '300', 'Betulaceae', 'Alnus', 'alnobetula', '(Regel) Raus', NULL),
  ('301', 'Alnus incana', 'Accepted', '301', 'Betulaceae', 'Alnus', 'incana', '(L.) Moench', NULL),
  ('400', 'Quercus borealis', 'Synonym', '101', 'Fagaceae', 'Quercus', 'borealis', 'F.Michx.', NULL);

-- Fixture distributions
INSERT INTO wcvp_distributions (plant_locality_id, plant_name_id, area_code_l3, introduced) VALUES
  ('1', '100', 'ALB', '0'),
  ('2', '100', 'FLA', '0'),
  ('3', '100', 'NCA', '1'),
  ('4', '101', 'NCA', '0'),
  ('5', '200', 'NCA', '0');

-- Meta
INSERT INTO meta (key, value) VALUES ('built_at', '2026-03-01T00:00:00Z');
