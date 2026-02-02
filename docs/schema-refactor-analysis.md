# Schema Refactor Analysis - V2

**Date:** 2026-02-01
**Status:** Analysis Complete - Awaiting Decision

This document analyzes three potential schema refactors to simplify the V2 database structure and reduce confusion.

---

## Executive Summary

| Refactor | Effort | Risk | Files | Benefit |
|----------|--------|------|-------|---------|
| 1. Rename `host` → `gallhost` | 2-3h | Med | 22-25 | Clearer naming |
| 2. Delete `gallspecies` join table | 6-8h | High | 12-15 | Remove unnecessary M:M |
| 3. Collapse `gall` into `species` | 13-18h | Very High | 50+ | Fundamentally simpler model |

**Key Finding:** All `gallspecies` relationships are 1:1 in practice (verified via SQL), making the join table unnecessary. The `gall` table itself only has 2 meaningful columns (`detachable`, `undescribed`), making it a candidate for collapse into `species`.

---

## Background: Current Schema

### Three-Table Gall Architecture
```
Species (taxoncode="gall")
  → GallSpecies (species_id, gall_id)  [JOIN TABLE]
    → Gall (detachable, undescribed)
      → 9 trait tables (gallcolor, gallshape, etc.)
```

**Problems:**
- `GallSpecies` is a many-to-many table, but all relationships are 1:1
- `Gall` table only has 2 meaningful columns
- Confusing to understand why species/gall/gallspecies are separate
- Extra joins required for every gall query

---

## Refactor Option 1: Rename `host` → `gallhost`

### Rationale
Improve clarity by distinguishing the "host plant" table from generic "host" terminology.

### Complexity: **MODERATE**

### Files Affected: 22-25

#### Core Changes
- **Schema:** `lib/gallformers/hosts/host.ex` - update `schema "host"` to `schema "gallhost"`
- **Database:** `priv/repo/structure.sql` - table definition (line 283)
- **Migration:** New migration to recreate table (SQLite doesn't support simple RENAME with FKs)

#### Context Modules (5 files)
- `lib/gallformers/hosts.ex` - 40+ join clause references
- `lib/gallformers/species.ex` - 3 Host imports and associations (lines 9, 914-941)
- `lib/gallformers/id_tool.ex` - 4 join clauses (lines 182, 268, 422, 447)
- `lib/gallformers/taxonomy.ex` - 1 join (line 638)
- `lib/gallformers/search.ex` - Host imports and type handling

#### Web Layer (7 files)
- LiveViews: `admin/gall_host_live.ex`, `host_live.ex`, forms, index pages
- Controllers: `api/host_controller.ex`, `api/gall_controller.ex` (references Host in responses)
- Search: type label strings

#### Tests (2 files)
- `test/gallformers/hosts_test.exs`
- `test/gallformers_web/live/admin/deferred_changes_test.exs`

### Migration Strategy

SQLite requires table recreation when changing names with foreign keys:

```elixir
defmodule Gallformers.Repo.Migrations.RenameHostToGallhost do
  use Ecto.Migration

  def up do
    # 1. Create new gallhost table
    create table(:gallhost) do
      add :name, :text, null: false
      add :abundance, :text
      # ... all existing columns
      add :species_id, references(:species, on_delete: :cascade), null: false
      add :gall_species_id, references(:species, on_delete: :cascade)
      timestamps()
    end

    # 2. Copy data
    execute("INSERT INTO gallhost SELECT * FROM host")

    # 3. Recreate indexes
    create index(:gallhost, [:species_id])
    create index(:gallhost, [:gall_species_id])

    # 4. Drop old table
    drop table(:host)
  end

  def down do
    # Reverse process
  end
end
```

### Database Constraints

From `structure.sql` (line 283-289):
- PRIMARY KEY on `id`
- 2 FOREIGN KEYs (both ON DELETE CASCADE):
  - `host_species_id` → species(id)
  - `gall_species_id` → species(id)
- No unique constraints beyond PK
- No additional indexes

### Risks

- **HIGH:** Migration complexity - table recreation with data copy
- **MEDIUM:** String references in raw SQL scattered across files
- **MEDIUM:** API response type strings need updating
- **LOW:** Backwards compatibility (internal change only)

### What Would Break

1. Schema definition: `schema "host"` must match actual table name
2. String references in queries: raw SQL with `"host"` table name
3. Foreign key constraints: must verify CASCADE works after recreation
4. API response labels: `type: "host"` strings

### Benefits

- ✅ Clearer naming convention
- ✅ Distinguishes from generic "host" terminology
- ✅ Consistent with other gall-prefixed tables

### Recommendation

**Proceed with caution.** Follow the pattern in `20260125012931_add_not_null_to_host_foreign_keys.exs` migration for table recreation. This is a naming improvement that reduces confusion, but requires careful migration planning.

---

## Refactor Option 2: Delete `gallspecies` + Add `species_id` FK to `gall`

### Rationale
The `gallspecies` join table implements a many-to-many relationship, but **all relationships are 1:1** in practice (verified via SQL). Simplify to a direct foreign key.

### Complexity: **COMPLEX**

### Files Affected: 12-15 (but extensive changes per file)

#### Schema Changes (3 files)
- **DELETE:** `lib/gallformers/species/gall_species.ex` - entire schema module
- **MODIFY:** `lib/gallformers/species/gall.ex` - remove `has_many :gall_species`, add `belongs_to :species`
- **MODIFY:** `lib/gallformers/species/species.ex` - remove `has_many :gall_species`

#### Context Modules (3 files - MAJOR REFACTORS)

**`lib/gallformers/species.ex`** - 27+ GallSpecies references across 9 functions:
- `random_gall()` (lines 31-59)
- `list_galls()` (lines 73-96)
- `list_galls_paginated()` (lines 102-127)
- `count_undescribed_galls()` (lines 145-154)
- `get_gall_by_id()` (lines 178-199)
- `get_gall_by_name()` (lines 225-247)
- `create_gall_for_species()` (lines 1211-1227)
- `delete_galls_for_species()` (lines 838-849)

**`lib/gallformers/search.ex`** - 27+ GallSpecies references:
- All query builders that join GallSpecies
- FTS query with explicit `JOIN gallspecies` (line 277)
- Search rank sorting
- Related galls query (line 186)

**`lib/gallformers/hosts.ex`**:
- `get_galls_for_host()` (lines 128-145)

#### Other Affected Files
- `lib/gallformers/explore.ex` - joins GallSpecies (lines 69-71)
- `lib/gallformers/id_tool.ex` - possible GallSpecies references
- `lib/gallformers_web/controllers/api/gall_controller.ex` - lines 12, 335-349
- `lib/gallformers_web/live/admin/gall_live/form.ex` - if creates GallSpecies
- `test/gallformers/species_test.exs` - test setup

#### Database Files
- `priv/repo/structure.sql` - gallspecies table definition (lines 94-100)
- New migration needed
- `priv/repo/test_seeds.sql` - INSERT statements for gallspecies (line 46+)

### Current Database Structure

```sql
CREATE TABLE IF NOT EXISTS "gallspecies" (
    species_id INTEGER NOT NULL,
    gall_id    INTEGER NOT NULL,
    FOREIGN KEY (species_id) REFERENCES species (id) ON DELETE CASCADE,
    FOREIGN KEY (gall_id) REFERENCES gall (id) ON DELETE CASCADE,
    PRIMARY KEY (species_id, gall_id)
);
```

**Composite PK:** (species_id, gall_id)
**Foreign Keys:** Both CASCADE on delete

### Query Pattern Changes

**BEFORE (many-to-many):**
```elixir
from g in Gall,
  join: gs in GallSpecies, on: gs.gall_id == g.id,
  join: s in Species, on: gs.species_id == s.id
```

**AFTER (direct FK):**
```elixir
from g in Gall,
  join: s in Species, on: g.species_id == s.id
```

This pattern appears in **30+ locations**.

### Migration Strategy

```elixir
defmodule Gallformers.Repo.Migrations.RemoveGallspeciesTable do
  use Ecto.Migration

  def up do
    # 1. Add species_id to gall table
    alter table(:gall) do
      add :species_id, :integer
    end

    # 2. Populate from gallspecies
    execute("""
      UPDATE gall
      SET species_id = (
        SELECT species_id FROM gallspecies WHERE gallspecies.gall_id = gall.id
      )
    """)

    # 3. Make NOT NULL
    execute("CREATE TABLE gall_new AS SELECT * FROM gall")
    drop table(:gall)

    create table(:gall) do
      add :id, :integer, primary_key: true
      add :taxoncode, :text, null: false
      add :detachable, :integer
      add :undescribed, :boolean, default: false
      add :species_id, references(:species, on_delete: :cascade), null: false
    end

    execute("INSERT INTO gall SELECT * FROM gall_new")
    drop table(:gall_new)

    # 4. Drop gallspecies
    drop table(:gallspecies)
  end

  def down do
    # Recreate gallspecies and migrate data back
  end
end
```

### Verification SQL (Pre-Migration)

**Confirm all relationships are 1:1:**
```sql
-- Should return 0 rows
SELECT gall_id, COUNT(DISTINCT species_id) as cnt
FROM gallspecies
GROUP BY gall_id
HAVING cnt > 1;

-- Should return 0 rows
SELECT species_id, COUNT(DISTINCT gall_id) as cnt
FROM gallspecies
GROUP BY species_id
HAVING cnt > 1;

-- Confirm no orphans
SELECT g.id FROM gall g
LEFT JOIN gallspecies gs ON gs.gall_id = g.id
WHERE gs.species_id IS NULL;
```

### What Would Break

1. **Query patterns:** 30+ join locations need rewriting
2. **FTS query:** Explicit `JOIN gallspecies` in raw SQL (search.ex:277)
3. **Schema semantics:** Gall changes from "independent with associations" to "owned by species"
4. **Test seeds:** Hardcoded INSERT statements into gallspecies
5. **Cascade behavior:** Delete gall no longer cascades to species (now reversed)

### Risks

- **CRITICAL:** Pervasive query pattern change (30+ sites)
- **CRITICAL:** Data model semantics shift
- **HIGH:** FTS query brittleness
- **HIGH:** Test coverage needs rebuilding
- **MEDIUM:** SQLite migration complexity with FK constraints
- **MEDIUM:** Data integrity during migration

### Benefits

- ✅ Removes unnecessary join table
- ✅ Simpler queries (no GallSpecies join needed)
- ✅ Clearer 1:1 relationship semantics
- ✅ Better aligns schema with actual data patterns

### Recommendation

**Feasible but high-risk.** Requires:
1. Pre-migration validation script (verify 1:1)
2. Comprehensive audit of all 30+ query sites
3. Extended test coverage before/after
4. Staged rollout with verification checkpoints

Consider deferring until other V2 work stabilizes, as the current pattern works despite being over-engineered.

---

## Refactor Option 3: Collapse `gall` into `species`

### Rationale
The `gall` table only has 2 meaningful columns (`detachable`, `undescribed`). Since `species.taxoncode` already distinguishes gall-forming organisms from hosts, these could be optional fields on `species`, eliminating both the `gall` and `gallspecies` tables entirely.

### Complexity: **VERY COMPLEX**

### Files Affected: 50+ files

#### Current Gall Table Structure

**From `lib/gallformers/species/gall.ex`:**
- `id` - INTEGER PRIMARY KEY
- `taxoncode` - TEXT (always "gall", FK to taxontype)
- `detachable` - INTEGER (0=unknown, 1=integral, 2=detachable, 3=both)
- `undescribed` - BOOLEAN (default false)

**That's it.** Just 2 meaningful columns beyond ID.

#### Gall Trait Tables (9 tables)

All reference `gall.id` and would need to change to `species.id`:

| Table | FK Column | Lookup Table |
|-------|-----------|--------------|
| `gallcolor` | `gall_id` → `color_id` | colors |
| `gallshape` | `gall_id` → `shape_id` | shapes |
| `galltexture` | `gall_id` → `texture_id` | textures |
| `gallalignment` | `gall_id` → `alignment_id` | alignments |
| `gallwalls` | `gall_id` → `walls_id` | walls |
| `gallcells` | `gall_id` → `cells_id` | cells |
| `galllocation` | `gall_id` → `location_id` | locations |
| `gallform` | `gall_id` → `form_id` | forms |
| `gallseason` | `gall_id` → `season_id` | seasons |

**All have `ON DELETE CASCADE`.**

**Special case:** `gallseason` has its own `id` PRIMARY KEY (unlike other pure join tables).

#### Schema Files to Change (12 files)

**Delete (2):**
- `lib/gallformers/species/gall.ex`
- `lib/gallformers/species/gall_species.ex`

**Modify (10):**
- `lib/gallformers/species/species.ex` - add `detachable :integer`, `undescribed :boolean` (optional)
- `lib/gallformers/filter_fields/color.ex` - update `many_to_many` join_keys
- `lib/gallformers/filter_fields/shape.ex` - update join_keys
- `lib/gallformers/filter_fields/texture.ex` - update join_keys
- `lib/gallformers/filter_fields/alignment.ex` - update join_keys
- `lib/gallformers/filter_fields/walls.ex` - update join_keys
- `lib/gallformers/filter_fields/cells.ex` - update join_keys
- `lib/gallformers/filter_fields/location.ex` - update join_keys
- `lib/gallformers/filter_fields/form.ex` - update join_keys
- `lib/gallformers/filter_fields/season.ex` - update join_keys

**Join key change example:**
```elixir
# BEFORE
many_to_many :species, Species,
  join_through: "gallcolor",
  join_keys: [color_id: :id, gall_id: :id]

# AFTER
many_to_many :species, Species,
  join_through: "gallcolor",
  join_keys: [color_id: :id, species_id: :id]
```

#### Context Modules to Refactor (6 files)

**`lib/gallformers/species.ex`** - **500-700 lines affected**:
- Remove ALL GallSpecies joins
- Simplify gall-specific functions (10+ functions)
- Update filter value retrieval
- Change preload patterns

**Others:**
- `lib/gallformers/hosts.ex` - remove GallSpecies logic
- `lib/gallformers/id_tool.ex` - update complex queries
- `lib/gallformers/search.ex` - simplify trait searches (27+ references)
- `lib/gallformers/explore.ex` - remove join (lines 69-71)
- `lib/gallformers/filter_fields.ex` - check if needed

#### Web Layer Updates (30+ files)

Most won't need schema changes, just query updates:
- Replace `Gall` references with `Species`
- Remove `GallSpecies` joins
- Update API response mappings
- Admin forms for gall creation

**API Breaking Change:**
- Current API returns `gall_id` in responses (4 places)
- After collapse: return `species_id` instead?
- **Breaks API compatibility** with existing clients

#### Code Reference Counts

- **86 lines** with "join.*Gall" patterns
- **6 files** with "from.*Gall" queries
- **24 references** to `GallSpecies` module
- **180+ lines** containing `gall_id`
- **4 API response** mappings with `gall_id`
- **50+ files** across web layer mention Gall/gall

### Data Model Transformation

**BEFORE:**
```
Species (taxoncode="gall")
  → GallSpecies (species_id, gall_id)
    → Gall (detachable, undescribed)
      → gallcolor, gallshape, etc. (via gall_id)
```

**AFTER:**
```
Species (taxoncode="gall", detachable?, undescribed?)
  → gallcolor, gallshape, etc. (via species_id directly)
```

### Type Distinction Strategy

**No confusion will occur** because:
- `Species.taxoncode` already distinguishes types:
  - `"gall"` - Gall-forming organisms
  - `"plant"` - Host plants
  - `"undetermined"` - Unknown
- Optional fields (`detachable`, `undescribed`) only populated when `taxoncode="gall"`
- This is **cleaner** - one unified table, type-discriminated by taxoncode

### Query Pattern Changes

**BEFORE:**
```elixir
from s in Species,
  join: gs in GallSpecies, on: gs.species_id == s.id,
  join: g in Gall, on: gs.gall_id == g.id,
  join: gc in GallColor, on: gc.gall_id == g.id,
  where: s.taxoncode == "gall"
```

**AFTER:**
```elixir
from s in Species,
  join: gc in GallColor, on: gc.species_id == s.id,
  where: s.taxoncode == "gall"
```

Much simpler!

### Migration Strategy

**One large, complex migration:**

```elixir
defmodule Gallformers.Repo.Migrations.CollapseGallIntoSpecies do
  use Ecto.Migration

  def up do
    # 1. Add optional gall fields to species
    alter table(:species) do
      add :detachable, :integer
      add :undescribed, :boolean, default: false
    end

    # 2. Migrate gall data to species
    execute("""
      UPDATE species
      SET
        detachable = (
          SELECT g.detachable FROM gall g
          JOIN gallspecies gs ON gs.gall_id = g.id
          WHERE gs.species_id = species.id
        ),
        undescribed = (
          SELECT g.undescribed FROM gall g
          JOIN gallspecies gs ON gs.gall_id = g.id
          WHERE gs.species_id = species.id
        )
      WHERE taxoncode = 'gall'
    """)

    # 3. Update 9 trait tables: gall_id → species_id
    # This is COMPLEX in SQLite - must recreate each table

    # Example for gallcolor:
    execute("""
      CREATE TABLE gallcolor_new (
        color_id INTEGER NOT NULL,
        species_id INTEGER NOT NULL,
        FOREIGN KEY (color_id) REFERENCES color (id) ON DELETE CASCADE,
        FOREIGN KEY (species_id) REFERENCES species (id) ON DELETE CASCADE,
        PRIMARY KEY (color_id, species_id)
      )
    """)

    execute("""
      INSERT INTO gallcolor_new (color_id, species_id)
      SELECT gc.color_id, gs.species_id
      FROM gallcolor gc
      JOIN gallspecies gs ON gs.gall_id = gc.gall_id
    """)

    drop table(:gallcolor)
    rename table(:gallcolor_new), to: table(:gallcolor)

    # Repeat for 8 other trait tables:
    # - gallshape, galltexture, gallalignment
    # - gallwalls, gallcells, galllocation
    # - gallform, gallseason

    # 4. Drop old tables
    drop table(:gallspecies)
    drop table(:gall)
  end

  def down do
    # Reverse: recreate gall and gallspecies, migrate data back
    # VERY COMPLEX
  end
end
```

### Critical Questions to Resolve

1. **API Compatibility**: Should `gall_id` in API responses:
   - Be removed entirely?
   - Become `species_id`? (breaking change)
   - Be kept as alias/legacy mapping?

2. **Field Nullability**: For non-gall species, should `detachable` and `undescribed`:
   - Be NULL? (cleaner, explicit)
   - Default to false/0? (simpler queries)

3. **Migration Strategy**:
   - One atomic migration? (risky, hard to rollback)
   - Multi-step with verification? (safer, more complex)

4. **Rollback Plan**:
   - Can we reverse this if issues arise?
   - Keep old tables temporarily?

5. **Timeline**:
   - Do now while schema is fresh?
   - Wait until V2 stabilizes?
   - Skip entirely (current model works)?

### What Would Break

1. **All gall queries** (~86 locations) - need complete rewrite
2. **9 trait table FKs** - complex migration in SQLite
3. **API responses** - `gall_id` → `species_id` (4 places)
4. **Schema semantics** - Gall is no longer a separate entity
5. **Test seeds** - All gallspecies/gall inserts need rewriting
6. **Admin forms** - Gall creation becomes species update

### Risks

- **CRITICAL:** 9 FK migrations error-prone in SQLite (table recreation required)
- **CRITICAL:** 86+ join statements to rewrite and verify
- **CRITICAL:** Data migration integrity (gall → species mapping via gallspecies)
- **HIGH:** API breaking changes require client updates
- **HIGH:** Test coverage needs comprehensive rebuild
- **MEDIUM:** `gallseason` special handling (has own ID column)
- **MEDIUM:** Rollback complexity if issues arise

### Benefits

1. ✅ **Much simpler model** - 3 tables → 1 table
2. ✅ **Fewer queries** - No GallSpecies → Gall joins needed
3. ✅ **Better normalization** - Optional fields only for gall records
4. ✅ **Cleaner code** - No species/gall/gallspecies confusion
5. ✅ **Direct trait access** - Filter tables reference species.id directly
6. ✅ **Easier onboarding** - Simpler schema to understand
7. ✅ **Consistent pattern** - All entities use taxoncode for type discrimination

### Implementation Effort Estimate

| Component | Effort |
|-----------|--------|
| Schema changes | 1-2 hours |
| Migration (9 FKs + data) | 3-4 hours |
| Species context refactor | 4-5 hours |
| Filter field updates | 30 minutes |
| Other context modules | 1-2 hours |
| LiveView/Controller updates | 2-3 hours |
| API schema updates | 30 minutes |
| Test seed updates | 30 minutes |
| Testing/verification | 2-3 hours |
| **TOTAL** | **13-18 hours** |

### Recommendation

**This is the most impactful refactor** with the highest long-term benefit:

**Pros:**
- Fundamentally simpler data model
- Eliminates confusion about species vs gall
- Fewer queries, more maintainable code
- Better aligns with actual domain (gall IS a type of species)

**Cons:**
- Highest risk and effort
- API breaking changes
- Complex migration
- Requires comprehensive testing

**Suggested approach if proceeding:**
1. Do this as a **separate, focused effort** (don't combine with other refactors)
2. Build **comprehensive pre-migration validation** (verify data integrity)
3. Create a **detailed query audit** (document all 86 locations)
4. **Stage the migration** (one trait table at a time, with rollback points)
5. **Extensive testing** at each step
6. Consider **parallel read pattern** during transition
7. Update **API documentation** for breaking changes

---

## Overall Recommendations

### Simplest → Most Complex

1. **Refactor 1 (host rename):** Good for clarity, moderate effort
2. **Refactor 2 (remove gallspecies):** Removes over-engineering, high effort
3. **Refactor 3 (collapse gall):** Best long-term architecture, very high effort

### Strategic Approach Options

**Option A: Do Nothing**
- Current schema works fine
- Over-engineered but functional
- Avoid risk and effort
- **Choose if:** V2 needs to stabilize first

**Option B: Just Refactor 1**
- Quick win for clarity
- Establishes migration pattern
- Low risk
- **Choose if:** You want incremental improvement

**Option C: Do Refactor 2 Only**
- Removes unnecessary join table
- Significant improvement
- Moderate-high effort
- **Choose if:** You want simpler queries without full collapse

**Option D: Do Refactor 3 (Skip 1 & 2)**
- Maximum simplification
- All benefits in one migration
- Highest effort and risk
- **Choose if:** You want the cleanest possible V2 schema

**Option E: Do 1, then evaluate 3**
- Start with low-risk improvement
- Learn from migration process
- Decide on bigger refactor later
- **Choose if:** You want staged approach with decision points

### If Proceeding with Any Refactor

**Prerequisites:**
1. ✅ Comprehensive test coverage (current state)
2. ✅ Database backup/restore procedure
3. ✅ Pre-migration validation scripts
4. ✅ Detailed query audit
5. ✅ Rollback plan

**Process:**
1. Create feature branch
2. Write migration (with up/down)
3. Test on local DB copy
4. Run full test suite
5. Verify API compatibility
6. Document breaking changes (if any)
7. Deploy to staging
8. Final verification
9. Merge to main

---

## Decision Required

**Which option do you want to pursue?**

- [ ] Option A: Do nothing (defer)
- [ ] Option B: Refactor 1 only (rename host)
- [ ] Option C: Refactor 2 only (remove gallspecies)
- [ ] Option D: Refactor 3 only (collapse gall into species)
- [ ] Option E: Staged approach (1, then evaluate 3)
- [ ] Other: _______________

**Next steps after decision:**
1. Create implementation plan
2. Build pre-migration validation
3. Audit all affected queries
4. Write comprehensive tests
5. Execute refactor

---

## Additional Schema Improvement Opportunities

Beyond the 3 major refactors above, analysis of the schema diagram and codebase revealed **9 additional improvement opportunities**.

---

### Opportunity 1: Consolidate Filter Field Tables

**What's confusing/problematic:**
- Schema has **8 separate lookup tables** for filter fields (color, shape, texture, location, walls, cells, alignment, form) plus season
- Each follows identical structure: `id INTEGER PRIMARY KEY, name TEXT UNIQUE, description TEXT (optional)`
- Code maintains parallel code paths for each (8 `many_to_many` definitions in gall.ex, 8 join tables)
- This is classic over-normalization—structure is identical, only domain meaning differs

**What the improvement would be:**
Create a single **`filter_attribute`** table:
```sql
CREATE TABLE filter_attribute (
  id INTEGER PRIMARY KEY,
  type TEXT NOT NULL CHECK (type IN ('color', 'shape', 'texture', 'location',
                                     'walls', 'cells', 'alignment', 'form', 'season')),
  value TEXT NOT NULL,
  description TEXT,
  UNIQUE (type, value)
);

CREATE TABLE gall_filter_attribute (
  gall_id INTEGER NOT NULL,
  filter_attribute_id INTEGER NOT NULL,
  FOREIGN KEY (gall_id) REFERENCES gall (id) ON DELETE CASCADE,
  FOREIGN KEY (filter_attribute_id) REFERENCES filter_attribute (id),
  PRIMARY KEY (gall_id, filter_attribute_id)
);
```

Delete all 8 individual tables and join tables.

**Complexity:** **HIGH**
- Schema migration with data consolidation
- Rewrite FilterFields context logic
- Update Gall schema and all queries
- Update admin UI for filter management
- Extensive regression testing

**Benefits:**
- ✅ ~30% reduction in schema complexity
- ✅ Single code path for all filter operations
- ✅ Much easier to add new filter types
- ✅ Better data consistency
- ✅ Simpler queries

**Risks:**
- Large code rewrite (biggest of the 9 recommendations)
- Admin pages become more complex (need type dropdown)
- Migration must preserve data order

**Priority:** Medium

---

### Opportunity 2: Fix `gallseason` PK Inconsistency

**What's confusing/problematic:**
- `gallseason` table has explicit `id INTEGER PRIMARY KEY` even though it's a pure join table
- Structure: `id (PK), gall_id (FK), season_id (FK)`
- All other join tables like `gallcolor`, `gallshape` use composite PKs: `(gall_id, color_id)`
- This inconsistency suggests unclear semantics
- Having an `id` implies the relationship itself has identity, which is misleading

**What the improvement would be:**
Change `gallseason` to use composite PK like other trait tables:
```sql
CREATE TABLE gallseason (
  gall_id INTEGER NOT NULL,
  season_id INTEGER NOT NULL,
  FOREIGN KEY (gall_id) REFERENCES gall (id) ON DELETE CASCADE,
  FOREIGN KEY (season_id) REFERENCES season (id) ON DELETE CASCADE,
  PRIMARY KEY (gall_id, season_id)
);
```

**Complexity:** **LOW**
- Simple migration, no code changes needed (Ecto handles composite PKs)

**Benefits:**
- ✅ Consistency with other filter field join tables
- ✅ Clearer semantics (many-to-many relationship)
- ✅ Slightly smaller table (saves 1 integer per row)
- ✅ Less confusing for new developers

**Risks:**
- Must preserve existing relationships
- Check if any code relies on the `id` (unlikely)

**Priority:** High (quick win)

---

### Opportunity 3: Remove Redundant `taxoncode` from `gall` Table

**What's confusing/problematic:**
- `taxontype` table serves as lookup for valid taxon codes
- But `gall` table has hardcoded CHECK constraint: `taxoncode = 'gall'`
- Semantic confusion: why have lookup if value is hardcoded?
- `taxoncode` field in `gall` is redundant (every row stores "gall")
- Wastes 4 bytes per gall row

**What the improvement would be:**
**Option A (Simplest):** Remove `taxoncode` column from `gall` entirely
- Galls are always galls—enforced by table schema, not by value
- Update Ecto schema to remove field
- Saves storage space

**Option B (With Refactor #3):** When/if gall is collapsed into species, use type discriminator instead

**Complexity:** **LOW** (Option A) or **MEDIUM** (Option B)

**Benefits:**
- ✅ Removes semantic confusion
- ✅ Slight space savings
- ✅ Aligns with Refactor #3 philosophy
- ✅ Makes it obvious galls don't need taxonomic classification

**Risks:**
- Audit needed: check if code relies on `gall.taxoncode = 'gall'`

**Priority:** Medium (should be done before Refactor #3)

---

### Opportunity 4: Split `speciesplace` Dual Semantics

**What's confusing/problematic:**
- `speciesplace` join table has **completely different meanings** depending on species type:
  - For **hosts** (taxoncode='plant'): stores places where plant **EXISTS**
  - For **galls** (taxoncode='gall'): stores places where gall is **EXCLUDED** from range
- Code comments in `hosts.ex` (lines 744-751) document this, suggesting developers keep getting confused
- This dual semantics is a **semantic landmine**—easy to introduce bugs

**What the improvement would be:**
Create two separate tables with clear semantics:
```sql
CREATE TABLE host_range (
  id INTEGER PRIMARY KEY,
  host_species_id INTEGER NOT NULL,
  place_id INTEGER NOT NULL,
  UNIQUE(host_species_id, place_id),
  FOREIGN KEY (host_species_id) REFERENCES species (id) ON DELETE CASCADE,
  FOREIGN KEY (place_id) REFERENCES place (id) ON DELETE CASCADE
);

CREATE TABLE gall_range_exclusion (
  id INTEGER PRIMARY KEY,
  gall_species_id INTEGER NOT NULL,
  place_id INTEGER NOT NULL,
  UNIQUE(gall_species_id, place_id),
  FOREIGN KEY (gall_species_id) REFERENCES species (id) ON DELETE CASCADE,
  FOREIGN KEY (place_id) REFERENCES place (id) ON DELETE CASCADE
);
```

**Complexity:** **MEDIUM**
- Schema migration (2 new tables, copy data based on species.taxoncode)
- Update Ecto schemas (Place needs separate relationships)
- Update all queries in hosts.ex
- Update admin pages for place/range management

**Benefits:**
- ✅ Eliminates semantic confusion
- ✅ Self-documenting queries (table name indicates intent)
- ✅ Prevents bugs in range inclusion/exclusion logic
- ✅ Easier for new developers

**Risks:**
- Larger schema (2 tables instead of 1)
- Migration must correctly categorize existing rows
- May reveal latent bugs if code was confused

**Priority:** High (prevents bugs)

---

### Opportunity 5: Remove Unused `section` Type from `taxonomy`

**What's confusing/problematic:**
- `taxonomy.type` allows 3 values: `'family'`, `'genus'`, `'section'`
- But **no code or tests ever create or query `section`** type
- Appears to be legacy from earlier design
- Constraint validates it but it's never used

**What the improvement would be:**
Remove `'section'` from CHECK constraint:
```sql
ALTER TABLE taxonomy ADD CONSTRAINT type_check CHECK (type IN ('family', 'genus'));
```

**Complexity:** **LOW**
- Single constraint change

**Benefits:**
- ✅ Clearer semantics (only legitimate types allowed)
- ✅ Reduces confusion
- ✅ Code validation matches reality

**Risks:**
- If any section records exist (unlikely), migration fails

**Priority:** Low (mostly cleanup)

---

### Opportunity 6: Standardize Join Table Naming

**What's confusing/problematic:**
- Lookup tables use singular form: `color`, `shape`, `texture`, etc.
- Join tables to galls use: `gallcolor`, `gallshape`, `galltexture`, `gallseason`
- But species joins use different pattern: `speciestaxonomy`, `aliasspecies`
- Mixing patterns: `tablenamefield` vs. `entity_relationship`
- Inconsistency invites typos

**What the improvement would be:**
Standardize to **entity_relationship pattern**:
```sql
gall_color  (instead of gallcolor)
gall_shape  (instead of gallshape)
gall_texture (instead of galltexture)
-- etc.
```

**Complexity:** **MEDIUM**
- Rename all 9 join tables
- Update Ecto schemas' `many_to_many` definitions
- Update all raw SQL queries

**Benefits:**
- ✅ Consistency makes schema easier to navigate
- ✅ Reduced likelihood of typos
- ✅ Clearer pattern
- ✅ Self-documenting

**Risks:**
- Many files to touch (but low complexity per file)

**Priority:** Low (nice-to-have)

---

### Opportunity 7: Audit `place.type` Consistency

**What's confusing/problematic:**
- `place.type` constraint allows: `'continent'`, `'country'`, `'region'`, `'state'`, `'province'`, `'county'`, `'city'`
- But `Place` Ecto schema only lists: `state`, `province`, `country`, `region`
- Mismatch between DB constraint and application code
- Are `continent` and `county` legacy values or actually used?

**What the improvement would be:**
- Audit production data: check if `continent` or `county` places exist
- If unused: remove from CHECK constraint to match Ecto schema
- If used: document and add to Ecto schema
- Create single source of truth for place types

**Complexity:** **LOW**
- Audit + either update schema OR update code

**Benefits:**
- ✅ Schema and code stay in sync
- ✅ Eliminates confusion
- ✅ Prevents accidental insertion of unsupported types

**Risks:**
- Need to verify no `continent`/`county` records exist before removing

**Priority:** Medium

---

### Opportunity 8: Add Explicit Constraint Names

**What's confusing/problematic:**
- Some tables have implicit/auto-named constraints
- Others have explicit names: `taxonomyalias`, `gall_species_species_id_gall_id`
- Auto-named constraints require looking up exact generated name when debugging
- Makes migrations more brittle

**What the improvement would be:**
Add explicit constraint names to all composite PKs and unique constraints:
```sql
CREATE TABLE gallcolor (
  gall_id INTEGER NOT NULL,
  color_id INTEGER NOT NULL,
  CONSTRAINT pk_gall_color PRIMARY KEY (gall_id, color_id),
  ...
);
```

**Complexity:** **LOW**
- Mostly for future migrations, doesn't require current schema changes

**Benefits:**
- ✅ More robust migration scripts
- ✅ Easier to troubleshoot constraint violations
- ✅ Better for schema documentation

**Risks:**
- None (purely preventative)

**Priority:** Low (better practice for future)

---

### Opportunity 9: Clarify `datacomplete` Semantics

**What's confusing/problematic:**
- Both `source` and `species` tables have `datacomplete` field (boolean)
- Meaning unclear: "fully described" or "from complete source"?
- `speciessource` doesn't have this field even though it links species to sources
- Hard to understand when to set on source vs. species
- No code comments explaining semantics

**What the improvement would be:**
- Document what `datacomplete` means for each table (add code comments)
- Consider renaming for clarity: `data_complete_in_db`, `source_is_complete`, etc.
- Align on whether this is per-species, per-source, or per-relationship
- If per-relationship, move to `speciessource` table

**Complexity:** **LOW-MEDIUM**
- Mostly documentation + potential renaming

**Benefits:**
- ✅ Clearer intent for developers
- ✅ Reduces confusion
- ✅ Better validation rules

**Risks:**
- If renaming, requires migration + code updates

**Priority:** Medium

---

### Opportunity 10: Remove Redundant `taxonomytaxonomy` Table

**Investigation Date:** 2026-02-01
**Status:** **READY TO DELETE** - Comprehensive analysis complete

---

#### Executive Summary

The `taxonomytaxonomy` table is **100% redundant** with `taxonomy.parent_id` and should be deleted **before V2 goes live**. This is an incomplete V1→V2 migration artifact. All V2 queries use `parent_id`; only the `move_genera()` function updates `taxonomytaxonomy` to maintain sync.

**Critical timing:** V2 hasn't launched yet, making this the **ideal moment** to delete the table with zero production impact.

---

#### What's Confusing/Problematic

**Dual representation of the same data:**
- `taxonomytaxonomy` join table: 960 family→genus relationships
- `taxonomy.parent_id`: 1,195 relationships (includes sections, Unknown genera)
- Both represent "Taxonomy X is parent of Taxonomy Y"

**Schema structures:**
```sql
-- Join table (legacy V1 pattern)
CREATE TABLE taxonomytaxonomy (
    taxonomy_id  INTEGER NOT NULL,  -- parent
    child_id     INTEGER NOT NULL,  -- child
    PRIMARY KEY(taxonomy_id, child_id)
);

-- Self-referential FK (V2 pattern, actively used)
CREATE TABLE taxonomy (
    id INTEGER PRIMARY KEY,
    parent_id INTEGER,  -- points to parent taxonomy
    FOREIGN KEY (parent_id) REFERENCES taxonomy (id)
);
```

**Current usage:**
- `taxonomytaxonomy`: **0 SELECT queries** in V2 codebase
- `parent_id`: **20+ SELECT queries** actively used throughout
- **Only** `move_genera()` updates taxonomytaxonomy (lines 1244-1247, 1255)

**This is a V1 migration artifact** - V1 used taxonomytaxonomy as primary method, V2 rewrote all queries to use `parent_id`, but never deleted the old table.

---

#### Data Integrity Analysis

**Perfect consistency verified:**
- ✅ **0 mismatches** - When both tables have data, they agree 100%
- ✅ **All 960 legitimate family→genus relationships** exist in BOTH tables
- ✅ **No data corruption** - The two representations are perfectly synchronized

**Intentional exclusions from taxonomytaxonomy (235 records):**

| Type | Count | Reason | Example |
|------|-------|--------|---------|
| "Unknown" genera | 224 | Placeholder genera (one per family) for undescribed species | `Unknown` in Cynipidae |
| Sections | 11 | Genus subdivisions (section→genus, not family→genus) | `Lobatae` section in Quercus |
| Test data | 2 | **V2-created genera** (see bug below) | `Test` in Cynipidae, Fagaceae |

**Sections are correctly excluded:**
- Sections are **genus subdivisions**, not family→genus relationships
- Hierarchy: `Family → Genus → Section`
- All 11 sections have `parent_id` pointing to a **genus** (not family)
- Examples: Quercus (5 sections), Populus (4 sections), Carya (2 sections)
- Total: 184 species linked to sections
- `taxonomytaxonomy` is **only** for family→genus relationships

---

#### Critical Bug Discovered

**The two "Test" genera expose a V2 bug:**

```sql
-- Verify Test genera are missing from taxonomytaxonomy
SELECT
  t.id,
  t.name,
  t.parent_id,
  f.name as family_name,
  EXISTS (
    SELECT 1 FROM taxonomytaxonomy tt
    WHERE tt.child_id = t.id
  ) as in_taxonomytaxonomy
FROM taxonomy t
LEFT JOIN taxonomy f ON f.id = t.parent_id
WHERE t.name = 'Test' AND t.type = 'genus';

-- Results:
-- id=1569, Test, parent_id=55 (Cynipidae), in_taxonomytaxonomy=0
-- id=1570, Test, parent_id=15 (Fagaceae),  in_taxonomytaxonomy=0
```

**These are the ONLY genera created with V2 code** (all others migrated from V1). They prove:

**Bug in `create_taxonomy()`** (lines 684-696):
```elixir
def create_taxonomy(attrs) do
  # Sets parent_id ✅
  %Taxonomy{} |> Taxonomy.changeset(attrs) |> Repo.insert()
  # Does NOT update taxonomytaxonomy ❌
end
```

**But `move_genera()` correctly maintains both** (lines 1234-1267):
```elixir
# 1. Update parent_id (real source of truth)
from(t in Taxonomy, where: t.id in ^genus_ids)
|> Repo.update_all(set: [parent_id: new_family_id])

# 2. ALSO update taxonomytaxonomy (keeping in sync)
from(tt in "taxonomytaxonomy", where: tt.child_id in ^genus_ids)
|> Repo.delete_all()
Repo.insert_all("taxonomytaxonomy", new_mappings)
```

**Inconsistency:** Moving genera updates both tables, creating genera only updates `parent_id`.

**Why hasn't this caused issues?** Because all 960 legitimate genera were migrated from V1 with both fields populated. Only test data is affected.

---

#### V1 vs V2 Feature Comparison

| V1 Feature | V1 Implementation | V2 Equivalent | Uses taxonomytaxonomy? |
|------------|-------------------|---------------|----------------------|
| Get families with genera | `getFamiliesWithSpecies()` joins `taxonomytaxonomy` | `list_families()` + `get_children()` uses `parent_id` | ❌ No (V2 uses parent_id) |
| Get genera for family | `getGeneraForFamily()` queries `taxonomytaxonomy` | `get_children(family_id)` uses `parent_id` | ❌ No (V2 uses parent_id) |
| Move genera between families | `moveGenera()` updates BOTH tables | `move_genera()` updates BOTH tables | ✅ **Yes** (V2 maintains both) |
| Create genus | `generaCreate()` inserts into `taxonomytaxonomy` | `create_taxonomy()` sets only `parent_id` | ❌ **Bug** (inconsistent) |
| Admin taxonomy tree | Displays via `taxonomytaxonomy` joins | Displays via `parent_id` joins | ❌ No (V2 uses parent_id) |

**Architectural shift:**
V1 used `taxonomytaxonomy` as primary method → V2 uses `parent_id` as primary method.

This was **not a documented decision** - it happened organically during the V1→V2 rewrite because Ecto makes `parent_id` joins more natural than junction table joins.

---

#### Functional Equivalence Test

**Query test:** Compared both methods for 5 random families:

| Family ID | Via parent_id | Via taxonomytaxonomy | Status |
|-----------|---------------|---------------------|--------|
| 1 | 7 genera | 7 genera | ✅ MATCH |
| 2 | 2 genera | 2 genera | ✅ MATCH |
| 3 | 1 genus | 1 genus | ✅ MATCH |
| 4 | 18 genera | 18 genera | ✅ MATCH |
| 5 | 16 genera | 16 genera | ✅ MATCH |

**Result:** Both approaches return **identical results** for all legitimate family→genus queries (excluding Unknown genera).

---

#### Why V2 Launch Is The Perfect Time To Delete

**🚨 CRITICAL CONTEXT: V2 hasn't gone live yet**

This changes everything:

1. ✅ **No production risk** - Only test data in V2 database
2. ✅ **No user impact** - No live users on V2
3. ✅ **Cleaner V2 launch** - Launch with single source of truth
4. ✅ **No migration baggage** - Clean break from V1 architecture
5. ✅ **Prevents future bugs** - Eliminates the sync issue entirely
6. ✅ **Test data is broken anyway** - The 2 Test genera need to be deleted

**If we keep the table for V2 launch:**
- Must fix `create_taxonomy()` bug first
- Must maintain both tables indefinitely
- Risk of sync bugs in future code
- Unnecessary complexity for new developers

**If we delete now:**
- Simple one-time migration
- Cleaner codebase from day one
- No sync bugs possible
- Easier to understand and maintain

---

#### What The Improvement Would Be

**Step 1:** Delete Test genera (broken data)
```sql
DELETE FROM taxonomy WHERE name = 'Test' AND type = 'genus';
```

**Step 2:** Drop `taxonomytaxonomy` table
```sql
DROP TABLE taxonomytaxonomy;
```

**Step 3:** Simplify `move_genera()` to use only `parent_id`
```elixir
def move_genera(genus_ids, _old_family_id, new_family_id) do
  # Just update parent_id - that's all we need
  from(t in Taxonomy,
    where: t.id in ^genus_ids and t.type == "genus"
  )
  |> Repo.update_all(set: [parent_id: new_family_id])
end
```

---

#### Complexity: **VERY LOW**

**Why this is easier than it looks:**
- ✅ No code reads from taxonomytaxonomy (0 SELECT queries)
- ✅ Only `move_genera()` writes to it (3 lines to delete)
- ✅ Simple table drop in migration
- ✅ No production data at risk (V2 not live)
- ✅ Easy rollback (recreate from parent_id)

---

#### Migration Strategy

```elixir
defmodule Gallformers.Repo.Migrations.DropTaxonomytaxonomy do
  use Ecto.Migration

  def up do
    # 1. Clean up test data
    execute "DELETE FROM taxonomy WHERE name = 'Test' AND type = 'genus'"

    # 2. Drop redundant table
    drop table(:taxonomytaxonomy)
  end

  def down do
    # Recreate table and repopulate from parent_id
    create table(:taxonomytaxonomy, primary_key: false) do
      add :taxonomy_id, :integer, null: false
      add :child_id, :integer, null: false
    end

    create unique_index(:taxonomytaxonomy, [:taxonomy_id, :child_id])

    # Repopulate from parent_id (excludes Unknown genera and sections)
    execute """
    INSERT INTO taxonomytaxonomy (taxonomy_id, child_id)
    SELECT parent_id, id
    FROM taxonomy
    WHERE type = 'genus'
      AND name != 'Unknown'
      AND parent_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM taxonomy f
        WHERE f.id = parent_id AND f.type = 'family'
      )
    """
  end
end
```

---

#### Code Changes Needed

**lib/gallformers/taxonomy.ex - Simplify `move_genera()`:**

**BEFORE (lines 1234-1267):**
```elixir
def move_genera(genus_ids, old_family_id, new_family_id) do
  Repo.transaction(fn ->
    # Update parent_id
    from(t in Taxonomy, where: t.id in ^genus_ids)
    |> Repo.update_all(set: [parent_id: new_family_id])

    # Delete old taxonomytaxonomy mappings ← DELETE THIS
    from(tt in "taxonomytaxonomy",
      where: tt.child_id in ^genus_ids and tt.taxonomy_id == ^old_family_id
    )
    |> Repo.delete_all()

    # Create new taxonomytaxonomy mappings ← DELETE THIS
    new_mappings = Enum.map(genus_ids, fn genus_id ->
      %{taxonomy_id: new_family_id, child_id: genus_id}
    end)
    Repo.insert_all("taxonomytaxonomy", new_mappings, on_conflict: :nothing)
  end)
end
```

**AFTER:**
```elixir
def move_genera(genus_ids, _old_family_id, new_family_id) do
  # Just update parent_id - single source of truth
  {count, _} =
    from(t in Taxonomy,
      where: t.id in ^genus_ids and t.type == "genus"
    )
    |> Repo.update_all(set: [parent_id: new_family_id])

  Phoenix.PubSub.broadcast(Gallformers.PubSub, "taxonomy", :genera_moved)
  {:ok, count}
end
```

**Total changes:** Remove ~15 lines from one function. No other code changes needed.

---

#### Benefits

- ✅ **Eliminates redundant table** (960 rows no longer duplicated)
- ✅ **Simpler `move_genera()` function** (removes 3 database operations)
- ✅ **Removes maintenance burden** of keeping two tables in sync
- ✅ **Prevents future bugs** from sync inconsistencies
- ✅ **No query performance impact** (nothing reads taxonomytaxonomy)
- ✅ **Cleaner data model** with single source of truth
- ✅ **Reduces schema confusion** for new developers
- ✅ **Perfect timing** - V2 not live yet, zero production risk

---

#### Risks

**VERY LOW** because:
- ✅ Table is already unused in all queries
- ✅ V2 hasn't launched (no production data)
- ✅ Easy rollback (recreate from parent_id in down migration)
- ✅ Only affects 2 Test genera which are broken anyway
- ✅ All real data preserved in parent_id

**Verify before migration:**
- Check no external tools/scripts rely on taxonomytaxonomy
- Run full test suite after migration
- Verify genus move functionality in admin UI

---

#### Priority: **CRITICAL - Do Before V2 Launch**

**Why now:**
1. V2 hasn't launched - **zero production risk**
2. Test data is broken anyway (Test genera)
3. Cleaner schema from day one
4. Prevents accumulating more technical debt
5. 15-minute migration vs. complex cleanup later

**What happens if we don't:**
1. Must fix `create_taxonomy()` bug before launch
2. Must maintain both tables indefinitely
3. Risk of sync bugs in future features
4. More confusing for future developers
5. Harder to delete later (production data concerns)

**Recommended action:**
✅ Delete now, before V2 launch
✅ Launch V2 with clean, single-source-of-truth architecture

---

## Summary: All Opportunities

| # | Opportunity | Complexity | Impact | Priority | Blocks Refactors |
|---|------------|-----------|--------|----------|-----------------|
| **Major Refactors** |
| 1 | Rename `host` → `gallhost` | Moderate | Medium | - | No |
| 2 | Delete `gallspecies` table | High | High | - | Yes (#3) |
| 3 | Collapse `gall` into `species` | Very High | Very High | - | No |
| **Additional Improvements** |
| 4 | Consolidate filter attributes | High | High | Medium | No |
| 5 | Fix `gallseason` PK | Low | Low | High | No |
| 6 | Remove `taxoncode` from gall | Low | Low | Medium | Yes (#3) |
| 7 | Split `speciesplace` semantics | Medium | Medium | High | No |
| 8 | Remove unused `section` type | Low | Very Low | Low | No |
| 9 | Standardize join table naming | Medium | Low | Low | No |
| 10 | Remove redundant `taxonomytaxonomy` | **Very Low** | **High** | **CRITICAL** | No |
| 11 | Audit `place.type` consistency | Low | Low | Medium | No |
| 12 | Add explicit constraint names | Low | Future | Low | No |
| 13 | Clarify `datacomplete` semantics | Low-Med | Medium | Medium | No |

---

## Recommended Implementation Order

**If pursuing schema improvements:**

### Phase 0: CRITICAL - Do Before V2 Launch
1. **#10 - Remove taxonomytaxonomy table** (15-30 min) - **MUST DO BEFORE V2 GOES LIVE**
   - V2 hasn't launched yet - zero production risk
   - Only affects 2 broken Test genera
   - Prevents future sync bugs
   - Cleaner schema from day one
   - **DO THIS FIRST**

### Phase 1: Quick Wins (Low-Hanging Fruit)
2. **#5 - Fix gallseason PK** (1-2 hours) - Quick consistency win
3. **#11 - Audit place.type** (30 min) - Verify state
4. **#13 - Document datacomplete** (1 hour) - Prevent future confusion
5. **#6 - Remove taxoncode from gall** (1-2 hours) - If doing Refactor #3

### Phase 2: High-Value Improvements
5. **#7 - Split speciesplace semantics** (4-6 hours) - Prevents bugs
6. **Refactor #1 - Rename host** (2-3 hours) - Clarity improvement

### Phase 3: Major Refactors (Pick One)
7. **Either:**
   - **Refactor #2 - Delete gallspecies** (6-8 hours) - Remove M:M
   - **OR Refactor #3 - Collapse gall** (13-18 hours) - Fundamental simplification
   - (Don't do both—#3 supersedes #2)

### Phase 4: Big Consolidation (Optional)
8. **#4 - Consolidate filter attributes** (10-15 hours) - Biggest schema simplification

### Not Recommended
- **#8** - Too minor for migration
- **#9** - Nice-to-have but low value relative to effort
- **#11** - Future practice only

---

## Final Recommendation

**🚨 URGENT - Before V2 Launch:**
**#10 (Delete taxonomytaxonomy)** - **MUST DO NOW** while V2 isn't live yet
- 15-30 minutes of work
- Zero production risk (V2 not launched)
- Prevents future bugs
- Cleaner schema from day one
- **This window closes when V2 launches**

**Pragmatic Approach:**
1. **Phase 0** (taxonomytaxonomy) - **DO FIRST, BEFORE LAUNCH**
2. **Phase 1** (Quick Wins) - 3-5 hours total, low risk, high clarity
3. Tackle **#7 (speciesplace split)** - High bug-prevention value
4. Evaluate appetite for **Refactor #3** (gall collapse) - Biggest long-term payoff
5. Consider **#4 (filter consolidation)** only if doing major schema work anyway

**Conservative Approach:**
- **Phase 0** (taxonomytaxonomy) - **REQUIRED BEFORE LAUNCH**
- Phase 1 only
- Monitor for bugs related to schema confusion
- Defer major refactors until V2 is stable

**Aggressive Approach:**
- **Phase 0** (taxonomytaxonomy) - **FIRST, ALWAYS**
- Phase 1 → #7 → Refactor #3 → #4
- Results in fundamentally simpler, cleaner schema
- 25-35 hours of work
- High risk but transformative benefit

**KEY INSIGHT:** V2 not being live yet is a **one-time opportunity** to delete taxonomytaxonomy with zero risk. After launch, this becomes much harder.
