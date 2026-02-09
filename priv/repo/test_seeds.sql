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

-- Synthetic genera (unique names to avoid collisions)
INSERT INTO taxonomy (id, name, description, type, parent_id, is_placeholder, inserted_at, updated_at) VALUES
  (10, 'GenusAlpha', 'test genus alpha', 'genus', NULL, 0, '2026-01-01T00:00:00', '2026-01-01T00:00:00'),
  (11, 'GenusBeta', 'test genus beta', 'genus', NULL, 0, '2026-01-01T00:00:00', '2026-01-01T00:00:00');

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

-- Places
INSERT INTO place (id, name, code, type) VALUES
  (1, 'Alberta', 'AB', 'province'),
  (2, 'California', 'CA', 'state');

-- Host ranges: which hosts occur in which places
INSERT INTO host_range (species_id, place_id) VALUES
  (6, 2),   -- T. alpinus in California
  (8, 1),   -- M. arvensis in Alberta
  (8, 2),   -- M. arvensis in California
  (7, 2);   -- T. serpyllum in California

-- =============================================================================
-- Articles
-- =============================================================================
-- Note: Article tests use Ecto sandbox and create their own test data.
-- Do NOT seed articles here - it will break tests that expect an empty state.
