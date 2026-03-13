-- Test seed data for gallformers test database (V2 Schema)
-- This file is loaded after structure.sql to provide minimal data for tests
--
-- Keep this minimal - only add data that tests actually need

-- =============================================================================
-- Reference Data (required by foreign keys)
-- =============================================================================

-- Abundances (referenced by species)
INSERT INTO abundance (id, abundance) VALUES
  (1, 'common'),
  (2, 'uncommon'),
  (3, 'rare');

-- =============================================================================
-- Species (for search/FTS tests)
-- =============================================================================

-- Host plants (taxoncode = 'plant')
INSERT INTO species (id, name, taxoncode, datacomplete, abundance_id, inserted_at, updated_at) VALUES
  (1, 'Quercus alba', 'plant', false, 1, '2026-01-01T00:00:00', '2026-01-01T00:00:00'),
  (2, 'Quercus rubra', 'plant', false, 1, '2026-01-01T00:00:00', '2026-01-01T00:00:00'),
  (3, 'Quercus velutina', 'plant', false, 2, '2026-01-01T00:00:00', '2026-01-01T00:00:00'),
  (4, 'Acer rubrum', 'plant', false, 1, '2026-01-01T00:00:00', '2026-01-01T00:00:00'),
  (5, 'Acer saccharum', 'plant', false, 2, '2026-01-01T00:00:00', '2026-01-01T00:00:00');

-- Gall-forming species (taxoncode = 'gall')
INSERT INTO species (id, name, taxoncode, datacomplete, abundance_id, inserted_at, updated_at) VALUES
  (100, 'Andricus quercuscalifornicus', 'gall', false, 1, '2026-01-01T00:00:00', '2026-01-01T00:00:00'),
  (101, 'Amphibolips confluenta', 'gall', false, 2, '2026-01-01T00:00:00', '2026-01-01T00:00:00'),
  (102, 'Callirhytis quercuspunctata', 'gall', false, 3, '2026-01-01T00:00:00', '2026-01-01T00:00:00');

-- Gall traits (1:1 with gall species, species_id is PK+FK)
-- Note: detachable is now a string enum: 'unknown', 'integral', 'detachable', 'both'
INSERT INTO gall_traits (species_id, detachable, undescribed) VALUES
  (100, 'integral', false),
  (101, 'unknown', false),
  (102, 'integral', true);

-- =============================================================================
-- Aliases (for search tests)
-- =============================================================================

-- Note: type must be 'common' or 'scientific' per CHECK constraint
INSERT INTO alias (id, name, type, description, inserted_at, updated_at) VALUES
  (1, 'White Oak', 'common', '', '2026-01-01T00:00:00', '2026-01-01T00:00:00'),
  (2, 'Red Oak', 'common', '', '2026-01-01T00:00:00', '2026-01-01T00:00:00'),
  (3, 'Oak Apple Gall Wasp', 'common', '', '2026-01-01T00:00:00', '2026-01-01T00:00:00');

-- V2: Snake-case junction table name
INSERT INTO alias_species (alias_id, species_id) VALUES
  (1, 1),
  (2, 2),
  (3, 100);

-- =============================================================================
-- ID filter test data (genus+place interaction)
-- =============================================================================
-- Uses dedicated host species (6-8) and genera to avoid collisions with
-- hosts_test.exs and id_live_test.exs which create their own taxonomy links
-- for species 1-5.

-- Dedicated host plants for ID filter tests
INSERT INTO species (id, name, taxoncode, datacomplete, abundance_id, inserted_at, updated_at) VALUES
  (6, 'Thymus alpinus', 'plant', false, 1, '2026-01-01T00:00:00', '2026-01-01T00:00:00'),
  (7, 'Thymus serpyllum', 'plant', false, 1, '2026-01-01T00:00:00', '2026-01-01T00:00:00'),
  (8, 'Mentha arvensis', 'plant', false, 1, '2026-01-01T00:00:00', '2026-01-01T00:00:00');

-- Synthetic families and genera (unique names to avoid collisions)
INSERT INTO taxonomy (id, name, description, type, parent_id, is_placeholder, inserted_at, updated_at) VALUES
  (20, 'FamilyAlpha', 'Plant', 'family', NULL, false, '2026-01-01T00:00:00', '2026-01-01T00:00:00'),
  (21, 'FamilyBeta', 'Plant', 'family', NULL, false, '2026-01-01T00:00:00', '2026-01-01T00:00:00'),
  (10, 'GenusAlpha', 'test genus alpha', 'genus', 20, false, '2026-01-01T00:00:00', '2026-01-01T00:00:00'),
  (11, 'GenusBeta', 'test genus beta', 'genus', 21, false, '2026-01-01T00:00:00', '2026-01-01T00:00:00');

-- Link dedicated hosts to their genera
INSERT INTO species_taxonomy (species_id, taxonomy_id) VALUES
  (6, 10),   -- Thymus alpinus → GenusAlpha
  (7, 10),   -- Thymus serpyllum → GenusAlpha
  (8, 11);   -- Mentha arvensis → GenusBeta

-- Gall-host relationships using dedicated hosts
INSERT INTO gallhost (id, host_species_id, gall_species_id, inserted_at, updated_at) VALUES
  (1, 6, 100, '2026-01-01T00:00:00', '2026-01-01T00:00:00'),  -- gall 100 → T. alpinus (GenusAlpha)
  (2, 8, 100, '2026-01-01T00:00:00', '2026-01-01T00:00:00'),  -- gall 100 → M. arvensis (GenusBeta) — cross-genus!
  (3, 7, 101, '2026-01-01T00:00:00', '2026-01-01T00:00:00');   -- gall 101 → T. serpyllum (GenusAlpha only)

-- =============================================================================
-- Places and Hierarchy (ISO 3166-2 codes)
-- =============================================================================
-- The global migration inserts places with auto-generated IDs.
-- We clear everything and re-insert with controlled IDs for test assertions.

DELETE FROM host_range;
DELETE FROM gall_range;
DELETE FROM place_hierarchy;
DELETE FROM place;

-- Hierarchy structure: Continents → countries → subdivisions (no region level)
INSERT INTO place (id, name, code, type) VALUES
  (901, 'North America', 'XN', 'continent'),
  (902, 'United States', 'US', 'country'),
  (903, 'Canada', 'CA', 'country'),
  (904, 'Mexico', 'MX', 'country'),
  (905, 'Caribbean', 'XB', 'continent'),
  (906, 'Bahamas', 'BS', 'country'),
  (907, 'Europe', 'XE', 'continent'),
  (908, 'Romania', 'RO', 'country');

-- Test subdivisions (ISO 3166-2 codes)
INSERT INTO place (id, name, code, type) VALUES
  (1, 'Alberta', 'CA-AB', 'province'),
  (2, 'California', 'US-CA', 'state'),
  (3, 'Jalisco', 'MX-JAL', 'state'),
  (4, 'Bucharest', 'RO-B', 'state');

-- Hierarchy links (continents are top-level, no region)
INSERT INTO place_hierarchy (place_id, parent_id) VALUES
  (902, 901),  -- United States → North America
  (903, 901),  -- Canada → North America
  (904, 901),  -- Mexico → North America
  (906, 905),  -- Bahamas → Caribbean
  (908, 907),  -- Romania → Europe
  (1, 903),    -- Alberta → Canada
  (2, 902),    -- California → United States
  (3, 904),    -- Jalisco → Mexico
  (4, 908);    -- Bucharest → Romania

-- Host ranges: which hosts occur in which places (with precision)
INSERT INTO host_range (species_id, place_id, precision) VALUES
  (6, 2, 'exact'),      -- T. alpinus in California (exact)
  (8, 1, 'exact'),      -- M. arvensis in Alberta (exact)
  (8, 2, 'exact'),      -- M. arvensis in California (exact)
  (7, 2, 'exact'),      -- T. serpyllum in California (exact)
  (8, 902, 'country');   -- M. arvensis in United States (country-level)

-- European host + gall data for continent-scoping tests
INSERT INTO species (id, name, taxoncode, datacomplete, abundance_id, inserted_at, updated_at) VALUES
  (9, 'Quercus robur', 'plant', false, 1, '2026-01-01T00:00:00', '2026-01-01T00:00:00');

INSERT INTO host_range (species_id, place_id, precision) VALUES
  (9, 4, 'exact');     -- Q. robur in Bucharest (RO-B) — European host

-- Introduced range for distribution_type tests (T. serpyllum as introduced in Bahamas)
-- T. serpyllum (7) is only hosted by gall 101, which is already NA-scoped,
-- and Bahamas is in Caribbean (XB), so this doesn't affect continent scoping.
INSERT INTO host_range (species_id, place_id, precision, distribution_type) VALUES
  (7, 906, 'exact', 'introduced');    -- T. serpyllum introduced in Bahamas

-- European gall linked to European host
INSERT INTO species (id, name, taxoncode, datacomplete, abundance_id, inserted_at, updated_at) VALUES
  (103, 'Cynips quercusfolii', 'gall', false, 1, '2026-01-01T00:00:00', '2026-01-01T00:00:00');

INSERT INTO gall_traits (species_id, detachable, undescribed) VALUES
  (103, 'detachable', false);

INSERT INTO gallhost (id, host_species_id, gall_species_id, inserted_at, updated_at) VALUES
  (4, 9, 103, '2026-01-01T00:00:00', '2026-01-01T00:00:00');  -- gall 103 → Q. robur (Europe)

-- =============================================================================
-- Gall range (curated stored range for galls)
-- =============================================================================

-- Gall 100 (hosts: T. alpinus in US-CA, M. arvensis in CA-AB + US-CA + US country)
-- Curated range: all host range places EXCEPT MX-JAL (was previously excluded)
INSERT INTO gall_range (species_id, place_id, precision) VALUES
  (100, 2, 'exact'),      -- US-CA (from T. alpinus and M. arvensis)
  (100, 1, 'exact'),      -- CA-AB (from M. arvensis)
  (100, 902, 'country');   -- US (from M. arvensis country-level)

-- Gall 101 (host: T. serpyllum in US-CA)
INSERT INTO gall_range (species_id, place_id, precision) VALUES
  (101, 2, 'exact');       -- US-CA (from T. serpyllum)

-- Gall 103 (host: Q. robur in RO-B)
INSERT INTO gall_range (species_id, place_id, precision) VALUES
  (103, 4, 'exact');       -- RO-B (from Q. robur)

-- =============================================================================
-- Intermediate taxonomy ranks (subfamily, tribe)
-- =============================================================================

-- Gall family with intermediate ranks for testing
INSERT INTO taxonomy (id, name, description, type, rank, parent_id, is_placeholder, inserted_at, updated_at) VALUES
  (30, 'Cynipidae', 'Wasp', 'family', NULL, NULL, false, '2026-01-01T00:00:00', '2026-01-01T00:00:00'),
  (31, 'Cynipinae', NULL, 'intermediate', 'Subfamily', 30, false, '2026-01-01T00:00:00', '2026-01-01T00:00:00'),
  (32, 'Cynipini', NULL, 'intermediate', 'Tribe', 31, false, '2026-01-01T00:00:00', '2026-01-01T00:00:00'),
  (33, 'Andricus', 'test genus under tribe', 'genus', NULL, 32, false, '2026-01-01T00:00:00', '2026-01-01T00:00:00'),
  (34, 'Cynips', 'test genus under tribe', 'genus', NULL, 32, false, '2026-01-01T00:00:00', '2026-01-01T00:00:00'),
  (35, 'Unknown', NULL, 'genus', NULL, 30, true, '2026-01-01T00:00:00', '2026-01-01T00:00:00');

-- Species under intermediate-parented genera
INSERT INTO species (id, name, taxoncode, datacomplete, abundance_id, inserted_at, updated_at) VALUES
  (200, 'Andricus crystallinus', 'gall', false, 1, '2026-01-01T00:00:00', '2026-01-01T00:00:00'),
  (201, 'Cynips quercus', 'gall', false, 2, '2026-01-01T00:00:00', '2026-01-01T00:00:00');

INSERT INTO gall_traits (species_id, detachable, undescribed) VALUES
  (200, 'integral', false),
  (201, 'unknown', false);

INSERT INTO species_taxonomy (species_id, taxonomy_id) VALUES
  (200, 33),  -- A. crystallinus → Andricus (under Cynipini tribe)
  (201, 34);  -- C. quercus → Cynips (under Cynipini tribe)

-- =============================================================================
-- Glossary
-- =============================================================================

INSERT INTO glossary (id, word, definition, urls) VALUES
  (1, 'abscission', 'The natural detachment of parts of a plant, typically dead leaves and ripe fruit.', ''),
  (2, 'bivalved', 'Having or consisting of two valves or similar parts.', ''),
  (3, 'cynipid', 'A member of the family Cynipidae, gall wasps that induce galls on plants.', 'https://en.wikipedia.org/wiki/Cynipidae'),
  (4, 'detachable', 'A gall that can be separated from the host plant without tearing plant tissue.', '');

-- =============================================================================
-- Keys (for key_live_test and keys_live_test)
-- =============================================================================

INSERT INTO keys (id, slug, title, subtitle, authors, description, version, couplets, inserted_at, updated_at) VALUES
  (1, 'oak-parasite-key',
   'Key to parasitic wasps associated with oak gall wasps',
   'Hymenoptera: Cynipini',
   '[]',
   'Detailed taxon treatments including diagnoses and notes on ecology.',
   '2026-02-05',
   '{"1":{"leads":[{"text":"Wings fully developed.","images":[],"destination":{"type":"couplet","number":"2"}},{"text":"Wings reduced or absent.","images":[],"destination":{"type":"couplet","number":"4"}}]},"2":{"leads":[{"text":"Fore wing with complex venation, with two or more cells defined by veins.","images":[],"destination":{"type":"couplet","number":"3"}},{"text":"Fore wing with simple venation.","images":[],"destination":{"type":"couplet","number":"4"}}]},"3":{"leads":[{"text":"Fore wing with conspicuous stigma. Metasoma generally elongate and cylindrical.","images":[],"destination":{"type":"couplet","number":"4","label":"Ichneumonoidea"}},{"text":"Fore wing without stigma. Metasoma ovate.","images":[],"destination":{"type":"taxon","name":"Cynipoidea"}}]},"4":{"leads":[{"text":"Fore wing vein 2m-cu present. Second and third metasomal tergites clearly separated.","images":[],"destination":{"type":"taxon","name":"Ichneumonidae"}},{"text":"Fore wing vein 2m-cu absent. Second and third metasomal tergites fused.","images":[],"destination":{"type":"taxon","name":"Braconidae"}}]}}',
   '2026-01-01T00:00:00', '2026-01-01T00:00:00');

-- =============================================================================
-- Articles
-- =============================================================================
-- Note: Article tests use Ecto sandbox and create their own test data.
-- Do NOT seed articles here - it will break tests that expect an empty state.

-- =============================================================================
-- Reset sequences (Postgres doesn't auto-advance sequences for explicit IDs)
-- =============================================================================
-- When INSERT specifies an explicit id, the sequence is NOT advanced.
-- Without this, the next auto-generated id collides with seeded rows.
SELECT setval('abundance_id_seq', (SELECT MAX(id) FROM abundance));
SELECT setval('species_id_seq', (SELECT MAX(id) FROM species));
SELECT setval('alias_id_seq', (SELECT MAX(id) FROM alias));
SELECT setval('taxonomy_id_seq', (SELECT MAX(id) FROM taxonomy));
SELECT setval('gallhost_id_seq', (SELECT MAX(id) FROM gallhost));
SELECT setval('place_id_seq', (SELECT MAX(id) FROM place));
SELECT setval('glossary_id_seq', (SELECT MAX(id) FROM glossary));
SELECT setval('keys_id_seq', (SELECT MAX(id) FROM keys));
