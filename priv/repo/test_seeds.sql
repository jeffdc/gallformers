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
  (100, 'Andricus quercuscalifornicus', 'Oak Apple Gall Wasp'),
  (101, 'Amphibolips confluenta', ''),
  (102, 'Callirhytis quercuspunctata', '');

-- =============================================================================
-- Articles
-- =============================================================================
-- Note: Article tests use Ecto sandbox and create their own test data.
-- Do NOT seed articles here - it will break tests that expect an empty state.
