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
  (33, 'Andricus', NULL, 'genus', NULL, 32, false, '2026-01-01T00:00:00', '2026-01-01T00:00:00'),
  (34, 'Cynips', '', 'genus', NULL, 32, false, '2026-01-01T00:00:00', '2026-01-01T00:00:00'),
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
-- Cases for the pages on the new back-end
-- =============================================================================
-- `make test-db` converts every old table here into the new ones with the
-- catalog migration (`mix gallformers.catalog.migrate --curated
-- test/support/fixtures/catalog_migration`); these rows exist for the cases
-- the new pages show. The curated decisions they need are in that directory
-- (the gall form's name_suffixes.csv row, the scientific alias's aliases.csv
-- row). test/gallformers/catalog_migration/test_seeds_test.exs checks the
-- conversion.

-- A real host genus and family, and the genus Neuroterus under Cynipini.
-- The genus's description is a common name (the migration makes it one of
-- its taxon); the family's is its old type (dropped).
INSERT INTO taxonomy (id, name, description, type, rank, parent_id, is_placeholder, inserted_at, updated_at) VALUES
  (36, 'Neuroterus', NULL, 'genus', NULL, 32, false, '2026-01-01T00:00:00', '2026-01-01T00:00:00'),
  (40, 'Fagaceae', 'Plant', 'family', NULL, NULL, false, '2026-01-01T00:00:00', '2026-01-01T00:00:00'),
  (41, 'Notholithocarpus', 'Tanoaks', 'genus', NULL, 40, false, '2026-01-01T00:00:00', '2026-01-01T00:00:00');

-- The host, native in California and introduced in Bucharest; data-complete
-- and common (editorial flags the migration carries onto its taxon)
INSERT INTO species (id, name, taxoncode, datacomplete, abundance_id, inserted_at, updated_at) VALUES
  (10, 'Notholithocarpus densiflorus', 'plant', true, 1, '2026-01-01T00:00:00', '2026-01-01T00:00:00');

INSERT INTO species_taxonomy (species_id, taxonomy_id) VALUES
  (10, 41);

INSERT INTO host_range (species_id, place_id, precision, distribution_type) VALUES
  (10, 2, 'exact', 'native'),        -- US-CA
  (10, 4, 'exact', 'introduced');    -- RO-B

-- A genus placeholder plant ("Notholithocarpus spp"): the migration makes it
-- no taxon; its gallhost becomes a genus-level Host (the genus taxon) and its
-- host_range row moves to the genus. Its range is Mexico, country-level.
INSERT INTO species (id, name, taxoncode, datacomplete, abundance_id, genus_placeholder, inserted_at, updated_at) VALUES
  (11, 'Notholithocarpus spp', 'plant', false, 1, true, '2026-01-01T00:00:00', '2026-01-01T00:00:00');

INSERT INTO species_taxonomy (species_id, taxonomy_id) VALUES
  (11, 41);

INSERT INTO host_range (species_id, place_id, precision, distribution_type) VALUES
  (11, 904, 'country', 'native');    -- MX

-- 300/301: an agamic/sexgen pair of one species (one Inducer, two Galls)
-- 302/303: gall forms of one species; 302's name is read by its curated
--          name_suffixes.csv row (the form "(australis)" is no generation)
-- 304: an undescribed gall in a real genus (its Inducer is the genus)
INSERT INTO species (id, name, taxoncode, datacomplete, abundance_id, inserted_at, updated_at) VALUES
  (300, 'Andricus seedii (agamic)', 'gall', true, 1, '2026-01-01T00:00:00', '2026-01-01T00:00:00'),
  (301, 'Andricus seedii (sexgen)', 'gall', false, 2, '2026-01-01T00:00:00', '2026-01-01T00:00:00'),
  (302, 'Neuroterus seedatorius (australis) (agamic)', 'gall', false, 1, '2026-01-01T00:00:00', '2026-01-01T00:00:00'),
  (303, 'Neuroterus seedatorius (sexgen)', 'gall', false, 2, '2026-01-01T00:00:00', '2026-01-01T00:00:00'),
  (304, 'Andricus n-densiflorus-seed-gall', 'gall', false, 3, '2026-01-01T00:00:00', '2026-01-01T00:00:00');

INSERT INTO gall_traits (species_id, detachable, undescribed, gallformers_code) VALUES
  (300, 'detachable', false, NULL),
  (301, 'integral', false, NULL),
  (302, 'detachable', false, NULL),
  (303, 'integral', false, NULL),
  (304, 'integral', true, 'n-densiflorus-seed-gall');

INSERT INTO species_taxonomy (species_id, taxonomy_id) VALUES
  (300, 33), (301, 33), (304, 33),  -- → Andricus
  (302, 36), (303, 36);             -- → Neuroterus

INSERT INTO gallhost (id, host_species_id, gall_species_id, inserted_at, updated_at) VALUES
  (5, 10, 300, '2026-01-01T00:00:00', '2026-01-01T00:00:00'),
  (6, 10, 301, '2026-01-01T00:00:00', '2026-01-01T00:00:00'),
  (7, 10, 302, '2026-01-01T00:00:00', '2026-01-01T00:00:00'),
  (8, 10, 303, '2026-01-01T00:00:00', '2026-01-01T00:00:00'),
  (9, 10, 304, '2026-01-01T00:00:00', '2026-01-01T00:00:00'),
  (10, 11, 304, '2026-01-01T00:00:00', '2026-01-01T00:00:00');  -- the genus placeholder

-- 305: a host-scoped gall (`86e7`): its curated name_suffixes.csv row reads
--      "(on Notholithocarpus densiflorus)" as its Host qualifier, so its name
--      is derived with no override. No gallhost row, so the host's pages and
--      the ID tool's host filters list the same Galls as before.
INSERT INTO species (id, name, taxoncode, datacomplete, abundance_id, inserted_at, updated_at) VALUES
  (305, 'Cynips seedhostus (on Notholithocarpus densiflorus)', 'gall', false, 3, '2026-01-01T00:00:00', '2026-01-01T00:00:00');

INSERT INTO gall_traits (species_id, detachable, undescribed, gallformers_code) VALUES
  (305, 'unknown', false, NULL);

INSERT INTO species_taxonomy (species_id, taxonomy_id) VALUES
  (305, 34);                        -- → Cynips

-- Gall 300's aliases: a common name (a gall alias Fact) and a scientific
-- name (a synonym of its Inducer, as the test aliases.csv decides)
INSERT INTO alias (id, name, type, description, inserted_at, updated_at) VALUES
  (4, 'seed oak apple', 'common', '', '2026-01-01T00:00:00', '2026-01-01T00:00:00'),
  (5, 'Callirhytis seedii', 'scientific', '', '2026-01-01T00:00:00', '2026-01-01T00:00:00');

INSERT INTO alias_species (alias_id, species_id) VALUES
  (4, 300),
  (5, 300);

-- The host's aliases: a common name (a common name of its taxon) and a
-- scientific name (a synonym of its taxon, as the test aliases.csv decides)
INSERT INTO alias (id, name, type, description, inserted_at, updated_at) VALUES
  (6, 'tanoak', 'common', '', '2026-01-01T00:00:00', '2026-01-01T00:00:00'),
  (7, 'Lithocarpus densiflorus', 'scientific', '', '2026-01-01T00:00:00', '2026-01-01T00:00:00');

INSERT INTO alias_species (alias_id, species_id) VALUES
  (6, 10),
  (7, 10);

-- Gall 304's former label (a former_undescribed alias: a former_label alias
-- Fact) and informal code (a scientific alias the test aliases.csv decides
-- is a code): shown in the Gall page's names table, never as common names
INSERT INTO alias (id, name, type, description, inserted_at, updated_at) VALUES
  (8, 'Andricus q-seed-old-label', 'former_undescribed', '', '2026-01-01T00:00:00', '2026-01-01T00:00:00'),
  (9, 'q-seed-code', 'scientific', '', '2026-01-01T00:00:00', '2026-01-01T00:00:00');

INSERT INTO alias_species (alias_id, species_id) VALUES
  (8, 304),
  (9, 304);

-- Sources: 58 is the Gallformers Source (its species_source rows are the
-- Gallformers ID Notes); 59 a publication cited on Gall 300. Gall 300's
-- default description (useasdefault) is the citation, Gall 301's its note:
-- the migration makes each the Gall's default_source_id
INSERT INTO source (id, title, author, pubyear, link, citation, license, kind, inserted_at, updated_at) VALUES
  (58, 'Gallformers ID Notes', 'Gallformers Contributors', '2020', 'https://gallformers.org',
   'Gallformers ID Notes.', 'Public Domain / CC0', 'gallformers', '2026-01-01T00:00:00', '2026-01-01T00:00:00'),
  (59, 'Cynipid galls of the seed slope', 'Weld, L. H.', '1957', 'https://example.com/seed-slope',
   'Weld, L. H. 1957. Cynipid galls of the seed slope.', 'Public Domain / Copyright Expired',
   'publication', '2026-01-01T00:00:00', '2026-01-01T00:00:00');

INSERT INTO species_source (id, species_id, source_id, description, useasdefault, externallink) VALUES
  (1, 300, 58, 'The seed note: a round, detachable gall on the leaf underside.', false, ''),
  (2, 300, 59, 'The seed citation: Weld describes the agamic gall.', true, 'https://example.com/seed-slope#p12'),
  (3, 301, 58, 'The sexgen seed note: a tiny gall on the catkins.', true, '');

-- An image on a gall and one on its host
INSERT INTO image (id, path, species_id, creator, license) VALUES
  (1, 'gall/300/300_seed_original.jpg', 300, 'Seed Photographer', 'CC-BY'),
  (2, 'gall/10/10_seed_original.jpg', 10, 'Seed Photographer', 'CC-BY');

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
SELECT setval('source_id_seq', (SELECT MAX(id) FROM source));
SELECT setval('species_source_id_seq', (SELECT MAX(id) FROM species_source));
SELECT setval('image_id_seq', (SELECT MAX(id) FROM image));
-- Galls and taxa share entity_id_seq, which continues the species IDs (the
-- catalog migration moves it on past the taxa it creates).
SELECT setval('entity_id_seq', (SELECT MAX(id) FROM species));

-- Catalog vocabularies (trait_values, generation_values, ...) are not seeded
-- here: the catalog migration that `make test-db` runs after this file loads
-- them from the contract with the real loader (Catalog.load_vocab/1), so
-- traits.json stays the one source of truth.
