# V2 Schema Refactor - Design Document

**Date:** 2026-02-01
**Status:** Design Complete - Ready for Implementation
**Authors:** Claude + Jeff

---

## Section 1: Overview & Goals

**Goal:** Launch V2 with a clean, well-designed schema that eliminates technical debt from the V1→V2 migration. This is our one opportunity to fix foundational issues before production launch.

**Core Principles:**
1. **Simplicity** - Eliminate unnecessary tables and relationships
2. **Consistency** - Standardize patterns across the schema
3. **Performance** - Add missing indexes on all foreign keys
4. **Maintainability** - Clear naming, proper constraints, audit trails
5. **Type Safety** - Use schema constraints to enforce business rules

**Scope:** This refactor consolidates findings from two analyses:
- Code-based analysis (gall/gallspecies complexity, taxonomytaxonomy redundancy, speciesplace dual semantics)
- Independent schema audit (43 missing FK indexes, inconsistent patterns, naming issues)

**Timeline:** Pre-launch refactor (~5-6 days of focused work)

**Migration Strategy:** Ecto migrations transform current schema → target schema, then migrations are deleted post-launch. `structure.sql` becomes the source of truth going forward.

**Success Criteria:**
- Clean schema that's easy to understand and maintain
- All foreign keys indexed for performance
- Consistent patterns throughout
- Full audit trail on core entities
- Zero migration files post-launch

---

## Section 2: Structural Changes (Major Refactors)

These are the high-impact changes that fundamentally simplify the data model.

### 2.1 Delete `taxonomytaxonomy` Table

**Current:** Dual representation of parent-child relationships (both `taxonomy.parent_id` and `taxonomytaxonomy` junction table)

**Change:** Drop `taxonomytaxonomy` entirely, use only `parent_id`

**Rationale:**
- V2 code uses `parent_id` exclusively (0 queries read `taxonomytaxonomy`)
- Redundant data is kept in sync manually (`move_genera` updates both)
- `create_taxonomy()` only updates `parent_id` (sync bug)
- Test data already broken (2 "Test" genera missing from junction table)

**Impact:** Remove ~960 rows of redundant data, simplify `move_genera()` by ~15 lines

---

### 2.2 Gall Architecture - Class Table Inheritance

**Old Model (V1):**
```
Species (taxoncode='gall')
  → GallSpecies (many-to-many join table, but always 1:1)
    → Gall (only 2 columns: detachable, undescribed)
      → 9 trait tables (gallcolor, gallshape, etc.)
```

**New Model (V2):**
```
Species (base table for ALL organisms)
  → Gall_traits (1:1 extension for taxoncode='gall')
    → 6 multi-value trait junction tables
    → 3 single-value traits as FK columns
```

**Schema:**
```sql
-- Base table (all organisms: galls AND hosts)
CREATE TABLE species (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  taxoncode TEXT NOT NULL CHECK (taxoncode IN ('gall', 'plant', 'undetermined')),
  abundance_id INTEGER REFERENCES abundance(id) ON DELETE SET NULL,
  taxonomy_id INTEGER REFERENCES taxonomy(id),
  inserted_at TEXT,
  updated_at TEXT
);

-- Gall-specific traits (1:1 extension, only exists for taxoncode='gall')
CREATE TABLE gall_traits (
  species_id INTEGER PRIMARY KEY,  -- PK + FK enforces 1:1

  -- Single-value traits (FK columns)
  color_id INTEGER REFERENCES color(id) ON DELETE SET NULL,
  walls_id INTEGER REFERENCES walls(id) ON DELETE SET NULL,
  cells_id INTEGER REFERENCES cells(id) ON DELETE SET NULL,

  -- Gall-specific columns
  detachable TEXT CHECK (detachable IN ('unknown', 'integral', 'detachable', 'both')),
  undescribed BOOLEAN DEFAULT FALSE NOT NULL,

  FOREIGN KEY (species_id) REFERENCES species(id) ON DELETE CASCADE
);

-- Multi-value trait junction tables (6 tables)
CREATE TABLE gall_season (
  species_id INTEGER NOT NULL,
  season_id INTEGER NOT NULL,
  PRIMARY KEY (species_id, season_id),
  FOREIGN KEY (species_id) REFERENCES species(id) ON DELETE CASCADE,
  FOREIGN KEY (season_id) REFERENCES season(id)
);
-- Repeat for: gall_shape, gall_texture, gall_alignment, gall_plant_part, gall_form
```

**Single-value vs Multi-value Traits:**
- **Single-value** (FK columns in gall_traits): detachable, walls, cells, color, abundance
- **Multi-value** (junction tables): season, shape, texture, location, alignment, form

**Future-proof for hosts:**
```sql
-- When/if hosts get traits, add:
CREATE TABLE host_traits (
  species_id INTEGER PRIMARY KEY,
  -- host-specific columns here
  FOREIGN KEY (species_id) REFERENCES species(id) ON DELETE CASCADE
);
```

**Benefits:**
1. ✅ Clean separation - gall traits live in `gall_traits`, not polluting `species`
2. ✅ No NULL columns on host records
3. ✅ 1:1 relationship enforced by PK=FK pattern
4. ✅ Removes unnecessary `gallspecies` M:M table
5. ✅ Future-proof for `host_traits` table
6. ✅ Simpler queries for single-value traits (no join needed)

---

### 2.3 Fix `gall_season` Primary Key

**Current:** Surrogate `id` primary key (inconsistent with other trait junction tables)

**Change:** Composite primary key `(species_id, season_id)`

**Rationale:** Pure junction tables should use composite PKs (like gall_shape, gall_texture, etc.)

---

### 2.4 Split `speciesplace` Dual Semantics

**Current:** `speciesplace` has opposite meanings depending on species type:
- For hosts (taxoncode='plant'): "places where host EXISTS"
- For galls (taxoncode='gall'): "places EXCLUDED from gall's range"

**Change:** Create two separate tables:
```sql
CREATE TABLE host_range (
  species_id INTEGER NOT NULL,
  place_id INTEGER NOT NULL,
  PRIMARY KEY (species_id, place_id),
  FOREIGN KEY (species_id) REFERENCES species (id) ON DELETE CASCADE,
  FOREIGN KEY (place_id) REFERENCES place (id) ON DELETE CASCADE
);

CREATE TABLE gall_range_exclusion (
  species_id INTEGER NOT NULL,
  place_id INTEGER NOT NULL,
  PRIMARY KEY (species_id, place_id),
  FOREIGN KEY (species_id) REFERENCES species (id) ON DELETE CASCADE,
  FOREIGN KEY (place_id) REFERENCES place (id) ON DELETE CASCADE
);
```

**Rationale:** Opposite semantics in one table is a bug magnet. Table names should indicate intent.

---

### 2.5 Rename `host` → `gallhost`

**Current:** Table named `host` stores "which plant species host which gall-forming species"

**Change:** Rename to `gallhost` for clarity

**Rationale:**
- Distinguishes from generic "host" terminology
- Consistent with other gall-prefixed tables
- Clear that it's the gall↔host relationship table

---

## Section 3: Naming Changes

These changes improve clarity and avoid confusion/conflicts.

### 3.1 Rename `location` Table → `plant_part`

**Current:** `location` table stores where on the plant a gall forms (leaf, stem, bud, etc.)

**Problem:** Confusing with geographic `place` table - two different "where" concepts

**Change:**
```sql
-- Old
CREATE TABLE location (
  id INTEGER PRIMARY KEY,
  location TEXT UNIQUE NOT NULL,  -- Awkward: column name = table name
  description TEXT
);

-- New
CREATE TABLE plant_part (
  id INTEGER PRIMARY KEY,
  part TEXT UNIQUE NOT NULL,  -- "leaf", "stem", "bud", etc.
  description TEXT
);
```

**Junction table:** `galllocation` → `gall_plant_part`

**Rationale:**
- Clear distinction: `plant_part` = morphology, `place` = geography
- More accurate domain terminology
- Avoids `location.location` awkwardness

---

### 3.2 Drop `image.default` Column

**Current:** Boolean `default` column (reserved keyword, requires escaping)

**Change:** **Drop the column entirely**

**Rationale:** Image table now has `sort_order` - first image (order=1) is always the default. Column is redundant.

---

### 3.3 Standardize Junction Table Naming (Snake Case)

**Current:** Concatenated pattern: `gallcolor`, `gallshape`, `galltexture`, etc.

**Change:** Snake case pattern: `gall_color`, `gall_shape`, `gall_texture`, etc.

**Keep "gall" prefix** - Even though gall traits reference species via gall_traits, the junction tables are still gall-specific.

**Other junction tables:**
- `speciessource` → `species_source`
- `speciestaxonomy` → `species_taxonomy`
- `placeplace` → `place_hierarchy` (clearer intent for self-referential relationship)
- `aliasspecies` → `alias_species`
- `taxonomyalias` → `taxonomy_alias`

**Rationale:**
- Snake case is more readable
- Preserves domain semantics (gall traits belong to galls)
- `place_hierarchy` is much clearer than `placeplace`

---

## Section 4: Constraints & Indexes

These changes ensure data integrity and query performance.

### 4.1 Add Foreign Key Indexes (Critical for Performance)

**Problem:** 43 foreign key columns lack supporting indexes

**Change:** Add indexes on ALL foreign key columns

**Affected Tables & Indexes:**
```sql
-- Gall trait junction tables (6 tables × 2 FKs each = 12 indexes)
CREATE INDEX idx_gall_season_species ON gall_season(species_id);
CREATE INDEX idx_gall_season_season ON gall_season(season_id);
CREATE INDEX idx_gall_shape_species ON gall_shape(species_id);
CREATE INDEX idx_gall_shape_shape ON gall_shape(shape_id);
CREATE INDEX idx_gall_texture_species ON gall_texture(species_id);
CREATE INDEX idx_gall_texture_texture ON gall_texture(texture_id);
CREATE INDEX idx_gall_alignment_species ON gall_alignment(species_id);
CREATE INDEX idx_gall_alignment_alignment ON gall_alignment(alignment_id);
CREATE INDEX idx_gall_plant_part_species ON gall_plant_part(species_id);
CREATE INDEX idx_gall_plant_part_part ON gall_plant_part(plant_part_id);
CREATE INDEX idx_gall_form_species ON gall_form(species_id);
CREATE INDEX idx_gall_form_form ON gall_form(form_id);

-- Gall traits single-value FKs
CREATE INDEX idx_gall_traits_color ON gall_traits(color_id);
CREATE INDEX idx_gall_traits_walls ON gall_traits(walls_id);
CREATE INDEX idx_gall_traits_cells ON gall_traits(cells_id);

-- Host table
CREATE INDEX idx_gallhost_host_species ON gallhost(host_species_id);
CREATE INDEX idx_gallhost_gall_species ON gallhost(gall_species_id);

-- Species relationships
CREATE INDEX idx_species_source_species ON species_source(species_id);
CREATE INDEX idx_species_source_source ON species_source(source_id);
CREATE INDEX idx_species_taxonomy_species ON species_taxonomy(species_id);
CREATE INDEX idx_species_taxonomy_taxonomy ON species_taxonomy(taxonomy_id);

-- Alias relationships
CREATE INDEX idx_alias_species_alias ON alias_species(alias_id);
CREATE INDEX idx_alias_species_species ON alias_species(species_id);
CREATE INDEX idx_taxonomy_alias_taxonomy ON taxonomy_alias(taxonomy_id);
CREATE INDEX idx_taxonomy_alias_alias ON taxonomy_alias(alias_id);

-- Range tables
CREATE INDEX idx_host_range_species ON host_range(species_id);
CREATE INDEX idx_host_range_place ON host_range(place_id);
CREATE INDEX idx_gall_range_exclusion_species ON gall_range_exclusion(species_id);
CREATE INDEX idx_gall_range_exclusion_place ON gall_range_exclusion(place_id);

-- Place hierarchy
CREATE INDEX idx_place_hierarchy_parent ON place_hierarchy(parent_place_id);
CREATE INDEX idx_place_hierarchy_child ON place_hierarchy(child_place_id);

-- Species foreign keys
CREATE INDEX idx_species_abundance ON species(abundance_id);
CREATE INDEX idx_species_taxonomy ON species(taxonomy_id);

-- Image foreign keys
CREATE INDEX idx_image_species ON image(species_id);
CREATE INDEX idx_image_source ON image(source_id);
```

**Rationale:** Unindexed FKs cause full table scans on joins and CASCADE deletes

---

### 4.2 Add NOT NULL Constraints to Junction Tables

**Problem:** Some junction tables allow NULL foreign keys (violates relational model)

**Change:** All junction table FKs must be NOT NULL

**Affected:**
- All `gall_*` trait junction tables (both FKs NOT NULL)
- `place_hierarchy` (both parent_place_id and child_place_id)
- `host_range`, `gall_range_exclusion` (both FKs NOT NULL)

---

### 4.3 Add Unique Constraints + Placeholder Support

**Problem:** Taxonomy uniqueness + "Unknown" placeholder handling

**Solution: Add `is_placeholder` boolean**
```sql
CREATE TABLE taxonomy (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('family', 'genus', 'section')),
  parent_id INTEGER REFERENCES taxonomy(id) ON DELETE RESTRICT,
  is_placeholder BOOLEAN NOT NULL DEFAULT FALSE,
  -- ... other columns

  -- Unique constraint excludes placeholders
  CONSTRAINT unique_name_per_parent
    UNIQUE (name, parent_id)
    WHERE NOT is_placeholder
);
```

**How it works:**
- "Unknown" family: `is_placeholder=TRUE, parent_id=NULL` (only one)
- "Unknown" genus in each family: `is_placeholder=TRUE, parent_id=<family_id>` (many allowed)
- Regular genera: `is_placeholder=FALSE` (unique within family)

**Benefits:**
- Schema enforces placeholder pattern
- Display: auto-generate "Unknown (Tephritidae)"
- Queries: filter with `WHERE NOT is_placeholder`
- No more manual "Unknown-tephritidae" naming

---

### 4.4 Standardize ON DELETE Behavior

**Reference:** `/Users/jeff/dev/gallformers/docs/plans/2026-01-31-audit-trail-and-cascade-protection-design.md`

**Critical changes:**
1. `taxonomy.parent_id → taxonomy`: **RESTRICT**
2. `image.source_id → source`: **RESTRICT**
3. `species_taxonomy.taxonomy_id → taxonomy`: **RESTRICT**
4. `taxonomy.type_id → taxontype`: **RESTRICT**

**Action:** Map cascade decisions to new schema structure separately

**Note:** This is a comprehensive topic with full analysis in the audit trail design doc. After this schema refactor is complete, cascade decisions will be mapped to the new table structure.

---

### 4.5 Detachable: Column with CHECK Constraint

**Current:** Lookup table `detachable` referenced by `gall.detachable_id`

**Change:** Simple TEXT column on `gall_traits`
```sql
detachable TEXT CHECK (detachable IN ('unknown', 'integral', 'detachable', 'both'))
```

**Rationale:**
- Fixed 4-value enum doesn't need lookup table
- TEXT is more readable than INTEGER codes
- CHECK constraint enforces valid values
- "both" means gall can be either integral or detachable

**Migration Note:** Audit code for integer value usage (0/1/2/3) and convert to TEXT ('unknown', 'integral', 'detachable', 'both')

---

### 4.6 Composite Indexes for Common Queries

**Add indexes for frequent query patterns:**
```sql
-- Species filtered by taxoncode
CREATE INDEX idx_species_taxoncode_name ON species(taxoncode, name);

-- Images sorted by species and order
CREATE INDEX idx_image_species_sort ON image(species_id, sort_order);
```

**Rationale:** Multi-column indexes accelerate filtered and sorted queries

---

## Section 5: New Features (Timestamps & Audit)

These additions enable data quality tracking and accountability.

### 5.1 Add Timestamps to Core Tables

**Problem:** Only Phoenix-generated tables have `inserted_at`/`updated_at`. Core domain tables lack audit trails.

**Change:** Add timestamps to all major entities
```sql
-- Add to these tables:
ALTER TABLE species ADD COLUMN inserted_at TEXT;
ALTER TABLE species ADD COLUMN updated_at TEXT;

ALTER TABLE taxonomy ADD COLUMN inserted_at TEXT;
ALTER TABLE taxonomy ADD COLUMN updated_at TEXT;

ALTER TABLE source ADD COLUMN inserted_at TEXT;
ALTER TABLE source ADD COLUMN updated_at TEXT;

ALTER TABLE gallhost ADD COLUMN inserted_at TEXT;
ALTER TABLE gallhost ADD COLUMN updated_at TEXT;

ALTER TABLE alias ADD COLUMN inserted_at TEXT;
ALTER TABLE alias ADD COLUMN updated_at TEXT;
```

**Migration Strategy:**
- Existing records: set `inserted_at` and `updated_at` to migration timestamp (best we can do)
- New records: Phoenix automatically manages these via `timestamps()` in schema

**Benefits:**
- Can answer "when was this species added?"
- Track data quality over time
- Enable "recently added" features
- Consistent with Phoenix conventions

---

### 5.2 Comprehensive Audit Trail (ex_audit)

**Reference:** `/Users/jeff/dev/gallformers/docs/plans/2026-01-31-audit-trail-and-cascade-protection-design.md`

**New `versions` table:**
```sql
CREATE TABLE versions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,

  -- Core ex_audit fields
  entity_schema TEXT NOT NULL,      -- e.g., "species", "taxonomy"
  entity_id INTEGER NOT NULL,
  action TEXT NOT NULL,             -- "created", "updated", "deleted"
  patch BLOB NOT NULL,              -- EETF serialized record state
  recorded_at DATETIME NOT NULL,
  rollback BOOLEAN DEFAULT 0,

  -- User tracking
  user_id TEXT,                     -- Auth0 user ID
  user_name TEXT,                   -- Display name

  -- Deletion accountability
  deletion_reason TEXT              -- Required for sensitive deletes
);

CREATE INDEX idx_versions_entity ON versions(entity_schema, entity_id);
CREATE INDEX idx_versions_user ON versions(user_id);
CREATE INDEX idx_versions_recorded_at ON versions(recorded_at);
CREATE INDEX idx_versions_action ON versions(action);
```

**What it tracks:**
- All creates, updates, deletes on tracked entities
- Who made the change (user_id, user_name)
- When it happened (recorded_at)
- Full record state before/after (serialized in patch)
- Deletion reasons for accountability

**Restore capability:**
- Deserialize `patch` to get original record
- Re-insert with original ID (SQLite supports this)
- No cascade restore needed (RESTRICT prevents cascades)

**Note:** Implementation details in separate audit trail doc. This schema refactor just needs to include the `versions` table in target schema.

---

## Section 6: Complete Change Summary

This is the master checklist of all schema changes.

### 6.1 Tables to DELETE
| Table | Reason |
|-------|--------|
| `taxonomytaxonomy` | Redundant with `taxonomy.parent_id` |
| `gallspecies` | Replaced by direct 1:1 relationship |
| `speciesplace` | Split into `host_range` + `gall_range_exclusion` |
| `taxontype` | Unused descriptions, replaced with CHECK constraint |
| `detachable` (lookup table) | Replaced with TEXT column + CHECK constraint |
| `gall_color` (junction) | Single-value trait → FK column in gall_traits |
| `gall_walls` (junction) | Single-value trait → FK column in gall_traits |
| `gall_cells` (junction) | Single-value trait → FK column in gall_traits |
| `migration` | Legacy (keep only `schema_migrations`) |

---

### 6.2 Tables to RENAME
| Current Name | New Name | Reason |
|--------------|----------|--------|
| `gall` | `gall_traits` | Clearer as 1:1 extension of species |
| `host` | `gallhost` | Clarity - distinguish from generic "host" |
| `location` | `plant_part` | Distinguish from geographic `place` |
| `placeplace` | `place_hierarchy` | Self-documenting |
| `speciessource` | `species_source` | Snake case consistency |
| `speciestaxonomy` | `species_taxonomy` | Snake case consistency |
| `aliasspecies` | `alias_species` | Snake case consistency |
| `taxonomyalias` | `taxonomy_alias` | Snake case consistency |
| `gallshape` | `gall_shape` | Snake case consistency |
| `galltexture` | `gall_texture` | Snake case consistency |
| `gallalignment` | `gall_alignment` | Snake case consistency |
| `galllocation` | `gall_plant_part` | Snake case + rename location |
| `gallform` | `gall_form` | Snake case consistency |
| `gallseason` | `gall_season` | Snake case consistency |

---

### 6.3 Tables to CREATE
| Table | Purpose |
|-------|---------|
| `host_range` | Places where host plants exist (split from speciesplace) |
| `gall_range_exclusion` | Places excluded from gall range (split from speciesplace) |
| `versions` | Audit trail (ex_audit) |

---

### 6.4 Columns to ADD

**species table:**
```sql
ADD COLUMN inserted_at TEXT;
ADD COLUMN updated_at TEXT;
```

**gall_traits table (renamed from gall):**
```sql
-- Add single-value trait FKs
ADD COLUMN color_id INTEGER REFERENCES color(id) ON DELETE SET NULL;
ADD COLUMN walls_id INTEGER REFERENCES walls(id) ON DELETE SET NULL;
ADD COLUMN cells_id INTEGER REFERENCES cells(id) ON DELETE SET NULL;
```

**taxonomy table:**
```sql
ADD COLUMN is_placeholder BOOLEAN NOT NULL DEFAULT FALSE;
ADD COLUMN inserted_at TEXT;
ADD COLUMN updated_at TEXT;
```

**source, gallhost, alias tables:**
```sql
ADD COLUMN inserted_at TEXT;
ADD COLUMN updated_at TEXT;
```

---

### 6.5 Columns to DROP
| Table | Column | Reason |
|-------|--------|--------|
| `image` | `default` | Redundant - use `sort_order` instead |
| `gall_season` | `id` | Change to composite PK |
| `gall_traits` | `taxoncode` | Redundant (always 'gall') |

---

### 6.6 Columns to RENAME
| Table | Current | New | Reason |
|-------|---------|-----|--------|
| `plant_part` | `location` | `part` | Avoid column name = table name |
| `gall_traits` | `id` | `species_id` | Clearer as FK to species |

---

### 6.7 Foreign Keys to CHANGE

**Gall trait tables:**
```sql
-- Multi-value junction tables (6 tables): change gall_id → species_id
gall_season, gall_shape, gall_texture, gall_alignment, gall_plant_part, gall_form

-- gall_traits table: species_id becomes PK + FK
species_id INTEGER PRIMARY KEY REFERENCES species(id) ON DELETE CASCADE
```

**CASCADE → RESTRICT (from audit trail doc):**
```sql
taxonomy.parent_id → taxonomy (CASCADE → RESTRICT)
image.source_id → source (CASCADE → RESTRICT)
species_taxonomy.taxonomy_id → taxonomy (CASCADE → RESTRICT)
taxonomy.type_id → taxontype (NO ACTION → RESTRICT)
```

---

### 6.8 Constraints to ADD

**Unique constraints:**
```sql
-- Taxonomy: unique name per parent, excluding placeholders
CREATE UNIQUE INDEX idx_taxonomy_name_parent
  ON taxonomy(name, parent_id)
  WHERE NOT is_placeholder;
```

**CHECK constraints:**
```sql
-- Gall traits detachable values
ALTER TABLE gall_traits ADD CONSTRAINT check_detachable
  CHECK (detachable IS NULL OR detachable IN ('unknown', 'integral', 'detachable', 'both'));

-- Species taxoncode
ALTER TABLE species ADD CONSTRAINT check_taxoncode
  CHECK (taxoncode IN ('gall', 'plant', 'undetermined'));

-- Taxonomy types
ALTER TABLE taxonomy ADD CONSTRAINT check_type
  CHECK (type IN ('family', 'genus', 'section'));
```

**Primary key changes:**
```sql
-- gall_season: drop surrogate id, use composite
ALTER TABLE gall_season DROP COLUMN id;
ALTER TABLE gall_season ADD PRIMARY KEY (species_id, season_id);

-- gall_traits: species_id becomes PK
ALTER TABLE gall_traits DROP COLUMN id;
ALTER TABLE gall_traits ADD PRIMARY KEY (species_id);
```

---

### 6.9 Data Migrations Required

**1. Migrate gallspecies → gall_traits.species_id:**
```sql
UPDATE gall_traits
SET species_id = (
  SELECT species_id FROM gallspecies
  WHERE gallspecies.gall_id = gall_traits.id
);
```

**2. Migrate single-value traits to gall_traits columns:**
```sql
-- Color
UPDATE gall_traits
SET color_id = (SELECT color_id FROM gall_color WHERE gall_id = id LIMIT 1);

-- Walls
UPDATE gall_traits
SET walls_id = (SELECT walls_id FROM gall_walls WHERE gall_id = id LIMIT 1);

-- Cells
UPDATE gall_traits
SET cells_id = (SELECT cells_id FROM gall_cells WHERE gall_id = id LIMIT 1);
```

**3. Update multi-value junction tables (gall_id → species_id):**
```sql
-- Use gallspecies to map gall_id → species_id
UPDATE gall_season
SET species_id = (SELECT species_id FROM gallspecies WHERE gall_id = gall_season.gall_id);
-- Repeat for: gall_shape, gall_texture, gall_alignment, gall_plant_part, gall_form
```

**4. Migrate speciesplace → host_range + gall_range_exclusion:**
```sql
INSERT INTO host_range (species_id, place_id)
  SELECT species_id, place_id FROM speciesplace
  JOIN species ON species.id = speciesplace.species_id
  WHERE species.taxoncode = 'plant';

INSERT INTO gall_range_exclusion (species_id, place_id)
  SELECT species_id, place_id FROM speciesplace
  JOIN species ON species.id = speciesplace.species_id
  WHERE species.taxoncode = 'gall';
```

**5. Convert detachable lookup → TEXT values:**
```sql
UPDATE gall_traits
SET detachable = CASE detachable_id
  WHEN 0 THEN 'unknown'
  WHEN 1 THEN 'integral'
  WHEN 2 THEN 'detachable'
  WHEN 3 THEN 'both'
END;
```

**6. Set initial timestamps:**
```sql
UPDATE species SET inserted_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP;
UPDATE taxonomy SET inserted_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP;
UPDATE source SET inserted_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP;
UPDATE gallhost SET inserted_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP;
UPDATE alias SET inserted_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP;
```

---

## Next Steps

1. ✅ **Design complete** (this document)
2. ⏭️ **Write target schema DDL** (`structure.sql` as it should exist after all changes)
3. ⏭️ **Design migration strategy** (order of migrations, dependencies)
4. ⏭️ **Write Ecto migrations** (transform current → target)
5. ⏭️ **Test migrations** against dev database
6. ⏭️ **Update Ecto schemas** to match new structure
7. ⏭️ **Update application code** (queries, forms, LiveViews)
8. ⏭️ **Run full test suite**
9. ⏭️ **Migrate V1 production data** on cutover day
10. ⏭️ **Delete migration files** post-launch

---

## Open Questions

1. **Vocabulary table descriptions:** Should all vocab tables have `description` column? (Currently inconsistent)
2. **Composite indexes:** Beyond the identified ones, are there other query patterns that need multi-column indexes?
3. **Audit trail scope:** Which tables should be tracked by ex_audit? (All major entities, or more selective?)
4. **Detachable code audit:** How extensive is the use of integer codes (0/1/2/3) vs TEXT in application code?

---

## References

- Original schema analysis: `/Users/jeff/dev/gallformers/docs/schema-refactor-analysis.md`
- Independent schema audit: `/Users/jeff/dev/gallformers/docs/2026-02-01-schema-independent-analysis.md`
- Audit trail design: `/Users/jeff/dev/gallformers/docs/plans/2026-01-31-audit-trail-and-cascade-protection-design.md`
- Current schema: `/Users/jeff/dev/gallformers/priv/repo/structure.sql`
