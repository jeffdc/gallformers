# Species Context Refactor: Analysis Reference

> **Purpose**: Detailed function inventory, dependency map, and Ecto audit for `species.ex`.
> Load this file only when you need the full context for a specific extraction step.

## File Stats

| Metric | Value |
|--------|-------|
| Lines | 845 |
| Commits | 20 |
| Public functions | 27 |
| Private functions | 18 |
| Cross-file references | 40 (highest in codebase) |
| Avg function length | 18 lines |

## Function Inventory (27 public functions)

### Basic CRUD (7 functions)

| Function | Lines | Touches Outside Domain? | Called From |
|----------|-------|------------------------|------------|
| `list_species/0` | 22-24 | No | (only test) |
| `get_species/1` | 30-32 | No | gall_live/form, gall_host_live, images_live, image_audit_live, add_from_source, quick_find |
| `get_species!/1` | 38-40 | No | gall_live/form, gall_live/index, internal (do_rename_species) |
| `list_species_by_ids/1` | 48-59 | No | genus_live, family_live, taxonomy_controller |
| `change_species/2` | 494 | No | gall_live/form (3 sites) |
| `create_species/1` | 502-516 | No | gall_live/form |
| `update_species/2` | 522-536 | No | gall_live/form |

### Species Enrichment (2 functions)

| Function | Lines | Touches Outside Domain? | Called From |
|----------|-------|------------------------|------------|
| `enrich_with_common_names_and_counts/1` | 70-97 | **Yes** — calls `GallHosts.get_host_counts_for_galls/1` and `GallHosts.get_gall_counts_for_hosts/1` | genus_live, section_live |
| `list_species_by_ids/1` (see CRUD) | 48-59 | No | (feeds into enrichment pipeline) |

### Image & Alias Queries (4 functions)

| Function | Lines | Touches Outside Domain? | Called From |
|----------|-------|------------------------|------------|
| `get_images_for_species/1` | 103-124 | **Yes** — queries `Image` schema + `Source` join | gall_live (public), host_live (public), gall_controller (API) |
| `get_aliases_for_species/1` | 130-143 | No (Alias is in Species domain) | gall_live (public), host_live (public), gall_controller (API), gall_live/form (admin, 3 sites) |
| `get_aliases_for_species_batch/1` | 153-170 | No | gall_controller (API), internal (enrichment) |
| `list_abundances/0` | 176-178 | No | gall_live/form, host_live/form |
| `get_abundance/1` | 184-186 | No | (only test) |

### Search (5 public + 4 private functions)

| Function | Lines | Touches Outside Domain? | Called From |
|----------|-------|------------------------|------------|
| `search_species/2` | 200-209 | No | gall_live/form, gall_live/index, host_live/form, add_from_source |
| `search_species_fts/2` | 269-300 | **Yes** — calls `Search.Ranking.parse_query/1` and `Ranking.add_scores_and_sort/2` | (internal, exposed for tests) |
| `search_species_like/2` | 319-321 | No | (fallback, no external callers) |
| `sanitize_fts_query/1` | 329-334 | No | search.ex (2 sites) |
| `search_species_by_name/3` | 407-415 | No | gall_live/form, gall_host_live (2 sites) |

Private helpers: `search_species_like_impl/2` (212-224), `search_species_with_terms/2` (226-256), `search_species_by_name_fts/3` (418-456), `search_species_by_name_like/3` (461-484)

### FTS Index Management (3 functions)

| Function | Lines | Touches Outside Domain? | Called From |
|----------|-------|------------------------|------------|
| `update_species_fts/1` | 342-361 | No (raw SQL on `species_fts`) | plants.ex (2 sites), internal (after create/update/alias) |
| `delete_species_fts/1` | 369-374 | No | plants.ex, internal (delete_species) |
| `rebuild_species_fts/0` | 382-398 | No | (only test, maintenance) |

### Rename / Alias Management (8 functions)

| Function | Lines | Touches Outside Domain? | Called From |
|----------|-------|------------------------|------------|
| `rename_species/4` | 590-596 | No | form_helpers (2 sites) |
| `add_rename_alias/3` | 619-639 | No | internal (rename, genus change) |
| `has_former_undescribed_alias?/1` | 645-652 | No | gall_live/form, internal |
| `rotate_former_undescribed_alias/1` | 664-680 | No | form_helpers, taxonomy.ex |
| `rename_for_genus_change/5` | 699-719 | No | taxonomy.ex (2 sites — genus rename + cascade) |
| `species_name_exists?/1` | 553-556 | No | internal (rename guard) |
| `find_species_with_alias/1` | 565-577 | No | gall_live/form (2), host_live/form (2) |
| `touch/1` | 542-547 | No | gall_live/form |

### Alias CRUD (2 functions)

| Function | Lines | Touches Outside Domain? | Called From |
|----------|-------|------------------------|------------|
| `create_alias_for_species/2` | 780-810 | No | gall_live/form (2 sites), plants.ex |
| `remove_alias_from_species/2` | 817-827 | No | gall_live/form, plants.ex |

### Deletion (1 function)

| Function | Lines | Touches Outside Domain? | Called From |
|----------|-------|------------------------|------------|
| `delete_species/1` | 752-771 | **Yes** — calls `Images.delete_images_from_s3_for_species/1` and `Galls.delete_gall_traits/1` | gall_live/form, gall_live/index |

### PubSub (1 public + 2 private)

| Function | Lines | Called From |
|----------|-------|------------|
| `subscribe/0` | 833-835 | gall_live/form, gall_live/index |

## Dependency Map

### Outbound Dependencies (what Species calls into)

| Module | What's Used | Lines |
|--------|------------|-------|
| `Ecto.Query` | Imported — `from`, `where`, `join`, etc. | 10 |
| `Gallformers.Repo` | All DB operations | throughout |
| `Gallformers.Images.Image` | Schema in `get_images_for_species` query | 104 |
| `Gallformers.Search.Ranking` | `parse_query/1`, `add_scores_and_sort/2` | 276-293 |
| `Gallformers.GallHosts` | `get_host_counts_for_galls/1`, `get_gall_counts_for_hosts/1` | 84-85 |
| `Gallformers.Images` | `delete_images_from_s3_for_species/1` | 755 |
| `Gallformers.Galls` | `delete_gall_traits/1` | 759 |
| `Phoenix.PubSub` | `subscribe/0`, `broadcast/3` | 834, 838 |

### Inbound Dependencies (what calls into Species)

**Context layer (3 modules)**:
| Module | Functions Called |
|--------|----------------|
| `taxonomy.ex` | `rename_for_genus_change/5` (2 sites), `rotate_former_undescribed_alias/1` |
| `plants.ex` | `update_species_fts/1` (2), `delete_species_fts/1`, `create_alias_for_species/2`, `remove_alias_from_species/2` |
| `search.ex` | `sanitize_fts_query/1` (2 sites) |

**Admin LiveViews (9 files, 42 calls)**:
| Module | Functions Called | Call Count |
|--------|----------------|------------|
| `gall_live/form.ex` | 16 distinct functions | 23 |
| `host_live/form.ex` | `list_abundances`, `search_species`, `find_species_with_alias` (2) | 4 |
| `gall_live/index.ex` | `subscribe`, `get_species!`, `delete_species`, `search_species` | 4 |
| `gall_host_live.ex` | `search_species_by_name` (2), `get_species` | 3 |
| `form_helpers.ex` | `rotate_former_undescribed_alias`, `rename_species` (2) | 3 |
| `add_from_source.ex` | `search_species`, `get_species` | 2 |
| `images_live.ex` | `get_species` | 1 |
| `image_audit_live.ex` | `get_species` | 1 |
| `quick_find.ex` | `get_species` | 1 |

**Public LiveViews (4 files, 7 calls)**:
| Module | Functions Called |
|--------|----------------|
| `gall_live.ex` | `get_images_for_species`, `get_aliases_for_species` |
| `host_live.ex` | `get_images_for_species`, `get_aliases_for_species` |
| `genus_live.ex` | `list_species_by_ids`, `enrich_with_common_names_and_counts` |
| `section_live.ex` | `enrich_with_common_names_and_counts` |

**API controllers (2 files, 4 calls)**:
| Module | Functions Called |
|--------|----------------|
| `gall_controller.ex` | `get_images_for_species`, `get_aliases_for_species_batch`, `get_aliases_for_species` |
| `taxonomy_controller.ex` | `list_species_by_ids` |

**Schema-only references (13 files)**: Use `Gallformers.Species.Species` in queries but don't call context functions.

### Heaviest Consumers

1. **`gall_live/form.ex`** — 23 calls across 16 distinct functions. This is the primary admin CRUD surface for galls.
2. **`host_live/form.ex`** — 4 calls. Uses search, abundances, and alias collision detection.
3. **`gall_live/index.ex`** — 4 calls. Uses subscribe, search, delete.

## Ecto Practices Audit

### 1. Maps Returned Instead of Structs (8 functions)

| Function | Lines | What's Returned | Fix |
|----------|-------|----------------|-----|
| `list_species_by_ids/1` | 48-59 | `%{id:, name:, taxoncode:}` | Return `Species` structs, let callers select fields |
| `get_images_for_species/1` | 103-124 | `%{id:, path:, sort_order:, ...}` map | Return `Image` structs with source preload |
| `get_aliases_for_species/1` | 130-143 | `%{id:, name:, type:, description:}` | Return `Alias` structs — use `many_to_many :aliases` association |
| `get_aliases_for_species_batch/1` | 153-170 | Nested maps | Return `Alias` structs grouped by species_id |
| `search_species/2` | 200-209 | `%{id:, name:, taxoncode:, ...}` | Return `Species` structs with optional preloads |
| `search_species_fts/2` | 269-300 | `%{id:, name:, taxoncode:, ...}` | Return `Species` structs (requires reworking raw SQL) |
| `search_species_by_name/3` | 407-415 | `%{id:, name:, taxoncode:}` | Return `Species` structs |
| `find_species_with_alias/1` | 565-577 | `%{species_id:, species_name:, ...}` | Return `Alias` structs with `:species` preload |

### 2. Unused Associations (Species schema defines but context ignores)

| Association | Line in Schema | Used via Preload? | Used Instead |
|-------------|---------------|-------------------|--------------|
| `many_to_many :aliases` | 42-44 | **Never** | Raw `join: als in "alias_species"` (lines 131-133, 154-156, 229-230, 647-649, 665-667) |
| `many_to_many :taxonomies` | 46-48 | **Never** (in this context) | (Used by Taxonomy context directly) |
| `has_many :images` | 32 | **Never** | Manual query with `from(i in Image, ...)` (line 104) |
| `belongs_to :abundance` | 30 | **Never** | Manual `left_join: ab in Abundance` (line 233) |
| `has_one :gall_traits` | 33 | **Never** | (Called via Galls context) |

**5 of 10 schema associations are never used as preloads in this context.**

### 3. Raw Junction Table Strings

The string `"alias_species"` appears in **7 queries** across the file (lines 131, 155, 229, 633, 647, 666, 819). The `Alias` schema already defines `many_to_many :species` through this table, and `Species` defines `many_to_many :aliases` through it. All of these could use association-based preloads.

### 4. Raw SQL Where Ecto Would Work

| Location | Lines | What's Done | Could Be |
|----------|-------|-------------|----------|
| `search_species_fts/2` | 279-287 | `Repo.query(sql, ...)` with hand-rolled SQL | Acceptable — FTS5 MATCH syntax has no Ecto equivalent |
| `search_species_by_name_fts/3` | 432-449 | `Repo.query(sql, ...)` with hand-rolled SQL | Acceptable — same FTS5 reason |
| `update_species_fts/1` | 345-358 | Two `Repo.query(...)` calls for FTS maintenance | Acceptable — FTS5 virtual table |
| `delete_species_fts/1` | 370-373 | `Repo.query(...)` | Acceptable — FTS5 virtual table |
| `rebuild_species_fts/0` | 383-397 | `Repo.query(...)` | Acceptable — FTS5 virtual table |

**Verdict**: Raw SQL for FTS5 is justified (no Ecto equivalent). The non-FTS queries that use maps + raw joins are the real problems.

### 5. Presentation Logic in Context

| Function | Lines | Presentation Concern |
|----------|-------|---------------------|
| `enrich_with_common_names_and_counts/1` | 70-97 | Adds `:common_name` and `:count` keys to maps for display. This is a presentation enrichment function that combines data from multiple contexts. |
| `list_species_by_ids/1` | 48-59 | Returns a shaped map `%{id:, name:, taxoncode:}` specifically for list display |
| `get_images_for_species/1` | 103-124 | Includes `source_title` from join — only needed for display captions |

### 6. Parallel Single/Batch Functions

| Single | Batch | Used Together? |
|--------|-------|---------------|
| `get_aliases_for_species/1` (line 130) | `get_aliases_for_species_batch/1` (line 153) | Different callers — single used by public views and admin forms, batch used by enrichment and API. Same query shape, different aggregation. |

## Test Coverage

### Tested Functions

| describe Block | Lines | Functions Tested |
|----------------|-------|-----------------|
| `list_species/0` | 12-17 | Basic list return |
| `get_species/1` | 78-92 | Nil for missing, returns for valid |
| `get_species!/1` | 94-100 | Raises for missing |
| `get_images_for_species/1` | 138-159 | Empty for missing, field structure |
| `get_aliases_for_species/1` | 161-184 | Empty for missing, field structure |
| `list_abundances/0` | 212-217 | Basic list return |
| `get_abundance/1` | 219-223 | Nil for missing |
| `search_species_fts/2` | 229-289 | Valid query, prefix, multi-word, nonsense, empty, fields, limit |
| `search_species/2` | 291-311 | FTS fast path, LIKE fallback |
| `sanitize_fts_query/1` | 313-333 | Special chars, whitespace, empty, only-special |
| `update_species_fts/1` + `rebuild_species_fts/0` | 335-347 | Rebuild succeeds, search after rebuild |
| `search_species_by_name/3` | 349-376 | Prefix, taxoncode filter, LIKE fallback |
| `delete_species/1` | 378-409 | Deletes species + cascades gall_traits, raises for non-existent |

### Untested Functions

| Function | Risk |
|----------|------|
| `list_species_by_ids/1` | Low — simple query |
| `enrich_with_common_names_and_counts/1` | **Medium** — combines data from 3 queries, map merging logic |
| `get_aliases_for_species_batch/1` | Low — batch version of tested single |
| `change_species/2` | Low — delegates to changeset |
| `create_species/1` | **Medium** — includes FTS update + PubSub broadcast |
| `update_species/2` | **Medium** — includes FTS update + PubSub broadcast |
| `touch/1` | Low — simple timestamp update |
| `species_name_exists?/1` | Low — simple exists query |
| `find_species_with_alias/1` | **Medium** — used for collision detection in admin forms |
| `rename_species/4` | **High** — complex rename with transaction, alias creation, genus change |
| `add_rename_alias/3` | Medium — alias creation with former_undescribed logic |
| `has_former_undescribed_alias?/1` | Low — simple exists query |
| `rotate_former_undescribed_alias/1` | Medium — type rotation logic |
| `rename_for_genus_change/5` | **High** — called by taxonomy, involves name manipulation |
| `create_alias_for_species/2` | Medium — transaction + FTS update |
| `remove_alias_from_species/2` | Medium — junction table delete + FTS |
| `subscribe/0` | Low — PubSub wrapper |
| `search_species_like/2` | Low — wrapper for private impl |

### Test Quality Notes

- Many tests depend on seed data existing (`if length(galls) > 0`), making them conditionally skip assertions
- The test file mixes Species context tests with Galls context tests (lines 19-76 test `Galls.*` functions)
- `get_images_for_species` test checks for `:default` key (line 155) which isn't in the select map — possible stale test
- No tests for CRUD mutation path (create → verify → update → verify → delete)
- No tests for alias management (create_alias_for_species, remove_alias_from_species)
- No tests for rename workflow (rename_species, rename_for_genus_change)

## Consolidation Opportunities

### 1. Near-Duplicate Search Functions

Three search entry points with similar structure:

| Function | FTS variant | LIKE fallback | Filter | Return shape |
|----------|-------------|---------------|--------|-------------|
| `search_species/2` | `search_species_fts/2` | `search_species_like_impl/2` | None | `%{id, name, taxoncode, datacomplete, abundance_name}` |
| `search_species_by_name/3` | `search_species_by_name_fts/3` | `search_species_by_name_like/3` | Optional taxoncode | `%{id, name, taxoncode}` |
| `search_species_like/2` | N/A | `search_species_like_impl/2` | None | Same as `search_species` |

These could potentially be unified into one `search_species/2` with an opts keyword list:
- `:taxoncode` — optional filter
- `:fields` — `:full` (with datacomplete/abundance) or `:name_only`
- `:strategy` — `:hybrid` (default, FTS + LIKE fallback), `:like_only`, `:fts_only`

### 2. Functions That Don't Belong in This Module

| Function | Lines | Better Home | Reason |
|----------|-------|-------------|--------|
| `get_images_for_species/1` | 103-124 | `Gallformers.Images` | Queries `Image` schema with `Source` join — Images context owns this domain |
| `enrich_with_common_names_and_counts/1` | 70-97 | Callers or a view-layer helper | Presentation enrichment that crosses GallHosts boundary |
| `sanitize_fts_query/1` | 329-334 | `Gallformers.Search` or `Gallformers.Search.Ranking` | Already called from `search.ex`; pure string utility not specific to Species |

### 3. Plants Delegation Pattern

Plants context (plants.ex) delegates alias and FTS operations to Species:
- `plants.ex:448` → `Gallformers.Species.create_alias_for_species/2`
- `plants.ex:458` → `Gallformers.Species.remove_alias_from_species/2`
- `plants.ex:344,364` → `Gallformers.Species.update_species_fts/1`
- `plants.ex:400` → `Gallformers.Species.delete_species_fts/1`

This is correct (Species owns aliases and FTS), but it means Species is the shared alias/FTS service for both galls and plants. If galls and plants become peer contexts, they'll both delegate to Species for these operations.

### 4. Dead Code Candidates

| Function | Evidence |
|----------|---------|
| `list_species/0` | Only called in test. 5000+ species — unlikely anyone wants an unfiltered list. |
| `get_abundance/1` | Only called in test. No web or context callers. |
| `search_species_like/2` | Public wrapper for private `search_species_like_impl/2`. No external callers found — `search_species/2` handles the fallback internally. |

### 5. Gall-Specific Logic in Species Context

| Function | Lines | Why It's Gall-Specific |
|----------|-------|----------------------|
| `delete_species/1` | 752-771 | Calls `Galls.delete_gall_traits/1` — hardcodes knowledge of gall domain |
| `enrich_with_common_names_and_counts/1` | 70-97 | Splits species by `taxoncode == "gall"` to get host vs gall counts |

When galls and plants become peer contexts, `delete_species` will need to delegate cleanup to the owning context rather than hardcoding `Galls.delete_gall_traits/1`.

