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
INSERT INTO species (id, name, taxoncode, datacomplete, abundance_id) VALUES
  (1, 'Quercus alba', 'plant', 0, 1),
  (2, 'Quercus rubra', 'plant', 0, 1),
  (3, 'Quercus velutina', 'plant', 0, 2),
  (4, 'Acer rubrum', 'plant', 0, 1),
  (5, 'Acer saccharum', 'plant', 0, 2);

-- Gall-forming species (taxoncode = 'gall')
INSERT INTO species (id, name, taxoncode, datacomplete, abundance_id) VALUES
  (100, 'Andricus quercuscalifornicus', 'gall', 0, 1),
  (101, 'Amphibolips confluenta', 'gall', 0, 2),
  (102, 'Callirhytis quercuspunctata', 'gall', 0, 3);

-- Gall traits (1:1 with gall species, species_id is PK+FK)
-- Note: detachable is now a string enum: 'unknown', 'integral', 'detachable', 'both'
INSERT INTO gall_traits (species_id, detachable, undescribed) VALUES
  (100, 'integral', 0),
  (101, 'unknown', 0),
  (102, 'integral', 1);

-- =============================================================================
-- Aliases (for search tests)
-- =============================================================================

-- Note: type must be 'common' or 'scientific' per CHECK constraint
INSERT INTO alias (id, name, type, description) VALUES
  (1, 'White Oak', 'common', ''),
  (2, 'Red Oak', 'common', ''),
  (3, 'Oak Apple Gall Wasp', 'common', '');

-- V2: Snake-case junction table name
INSERT INTO alias_species (alias_id, species_id) VALUES
  (1, 1),
  (2, 2),
  (3, 100);

-- =============================================================================
-- FTS Index (for full-text search tests)
-- =============================================================================

INSERT INTO species_fts (species_id, name, aliases) VALUES
  (1, 'Quercus alba', 'White Oak'),
  (2, 'Quercus rubra', 'Red Oak'),
  (3, 'Quercus velutina', ''),
  (4, 'Acer rubrum', ''),
  (5, 'Acer saccharum', ''),
  (6, 'Thymus alpinus', ''),
  (7, 'Thymus serpyllum', ''),
  (8, 'Mentha arvensis', ''),
  (100, 'Andricus quercuscalifornicus', 'Oak Apple Gall Wasp'),
  (101, 'Amphibolips confluenta', ''),
  (102, 'Callirhytis quercuspunctata', '');

-- =============================================================================
-- ID filter test data (genus+place interaction)
-- =============================================================================
-- Uses dedicated host species (6-8) and genera to avoid collisions with
-- hosts_test.exs and id_live_test.exs which create their own taxonomy links
-- for species 1-5.

-- Dedicated host plants for ID filter tests
INSERT INTO species (id, name, taxoncode, datacomplete, abundance_id) VALUES
  (6, 'Thymus alpinus', 'plant', 0, 1),
  (7, 'Thymus serpyllum', 'plant', 0, 1),
  (8, 'Mentha arvensis', 'plant', 0, 1);

-- Synthetic families and genera (unique names to avoid collisions)
INSERT INTO taxonomy (id, name, description, type, parent_id, is_placeholder, inserted_at, updated_at) VALUES
  (20, 'FamilyAlpha', 'test family alpha', 'family', NULL, 0, '2026-01-01T00:00:00', '2026-01-01T00:00:00'),
  (21, 'FamilyBeta', 'test family beta', 'family', NULL, 0, '2026-01-01T00:00:00', '2026-01-01T00:00:00'),
  (10, 'GenusAlpha', 'test genus alpha', 'genus', 20, 0, '2026-01-01T00:00:00', '2026-01-01T00:00:00'),
  (11, 'GenusBeta', 'test genus beta', 'genus', 21, 0, '2026-01-01T00:00:00', '2026-01-01T00:00:00');

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
DELETE FROM gall_range_exclusion;
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
INSERT INTO species (id, name, taxoncode, datacomplete, abundance_id) VALUES
  (9, 'Quercus robur', 'plant', 0, 1);

INSERT INTO species_fts (species_id, name, aliases) VALUES
  (9, 'Quercus robur', '');

INSERT INTO host_range (species_id, place_id, precision) VALUES
  (9, 4, 'exact');     -- Q. robur in Bucharest (RO-B) — European host

-- European gall linked to European host
INSERT INTO species (id, name, taxoncode, datacomplete, abundance_id) VALUES
  (103, 'Cynips quercusfolii', 'gall', 0, 1);

INSERT INTO gall_traits (species_id, detachable, undescribed) VALUES
  (103, 'detachable', 0);

INSERT INTO species_fts (species_id, name, aliases) VALUES
  (103, 'Cynips quercusfolii', '');

INSERT INTO gallhost (id, host_species_id, gall_species_id, inserted_at, updated_at) VALUES
  (4, 9, 103, '2026-01-01T00:00:00', '2026-01-01T00:00:00');  -- gall 103 → Q. robur (Europe)

-- =============================================================================
-- Gall range exclusions (gall 100 excludes Jalisco from its range)
-- =============================================================================

INSERT INTO gall_range_exclusion (species_id, place_id, precision)
VALUES
  (100, 3, 'exact');   -- Gall 100 excludes Jalisco (MX-JAL)

-- =============================================================================
-- Articles
-- =============================================================================
-- Note: Article tests use Ecto sandbox and create their own test data.
-- Do NOT seed articles here - it will break tests that expect an empty state.
