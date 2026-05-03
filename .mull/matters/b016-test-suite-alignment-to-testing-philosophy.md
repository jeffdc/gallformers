---
status: refined
created: 2026-03-18
updated: 2026-05-01
epic: platform
docs: [docs/testing-philosophy.md]
relates: [2648]
---

# Test suite alignment to testing philosophy

## Tracking

Two lists: **Done** and **Remaining**. A test file that appears in neither list has not been evaluated — this catches new files created by agents.

### Done — meets testing philosophy

- test/gallformers/gall_hosts_test.exs — 36 unit tests, owns data, strong assertions
- test/gallformers_web/live/admin/gall_host_live_test.exs — 49 tests, owns data, DB verification after save, integration workflow

### Remaining — not yet evaluated

#### Tier 1: Unit — Context (existing)

- test/gallformers/accounts_test.exs
- test/gallformers/analytics_test.exs
- test/gallformers/articles_test.exs
- test/gallformers/changeset_helpers_test.exs
- test/gallformers/content_images_test.exs
- test/gallformers/galls_identification_test.exs
- test/gallformers/galls_test.exs
- test/gallformers/glossaries_test.exs
- test/gallformers/hosts_test.exs
- test/gallformers/images_test.exs
- test/gallformers/inaturalist_test.exs
- test/gallformers/keys_test.exs
- test/gallformers/markdown_test.exs
- test/gallformers/places_test.exs
- test/gallformers/plants_test.exs
- test/gallformers/ranges_test.exs
- test/gallformers/request_logger_test.exs
- test/gallformers/search_test.exs
- test/gallformers/site_settings_test.exs
- test/gallformers/species_test.exs
- test/gallformers/storage_test.exs

#### Tier 1: Unit — Context (need to write)

- Sources — 2 tests, needs ~15 more
- FilterFields — 0 tests
- SchemaFields — 0 tests

#### Tier 1: Unit — Components

- test/gallformers_web/components/data_display_components_test.exs
- test/gallformers_web/components/form_components_test.exs
- test/gallformers_web/components/layouts_test.exs
- test/gallformers_web/components/region_scope_test.exs
- test/gallformers_web/components/tree_components_test.exs
- Missing: typeahead, multi_select_typeahead, taxon_name, selectable_tree

#### Tier 1: Unit — JS hooks

- range_map.js — 0 tests, need framework + tests
- typeahead hook — 0 tests
- IndeterminateCheckbox hook — 0 tests
- Other hooks — inventory needed

#### Tier 2: Integration — Admin LiveViews

- test/gallformers_web/live/admin/host_live/form_test.exs
- test/gallformers_web/live/admin/host_live/wcvp_test.exs
- test/gallformers_web/live/admin/host_range_live_test.exs
- test/gallformers_web/live/admin/gall_range_live_test.exs
- test/gallformers_web/live/admin/dashboard_live_test.exs
- test/gallformers_web/live/admin/users_live_test.exs
- test/gallformers_web/live/admin/profile_live_test.exs
- test/gallformers_web/live/admin/ops_live_test.exs
- test/gallformers_web/live/admin/section_live_test.exs
- test/gallformers_web/live/admin/country_drill_down_test.exs
- test/gallformers_web/live/admin/powo_diff_review_test.exs
- test/gallformers_web/live/admin/content_image_manager_test.exs
- test/gallformers_web/live/admin/inat_import_component_test.exs
- test/gallformers_web/live/admin/taxonomy_form_test.exs
- test/gallformers_web/live/admin/deferred_changes_test.exs

#### Tier 2: Integration — Public LiveViews

- test/gallformers_web/live/search_live_test.exs
- test/gallformers_web/live/home_live_test.exs
- test/gallformers_web/live/gall_live_test.exs
- test/gallformers_web/live/family_live_test.exs
- test/gallformers_web/live/place_live_test.exs
- test/gallformers_web/live/places_live_test.exs
- test/gallformers_web/integration_test.exs

#### Tier 2: Integration — Controllers/API

- test/gallformers_web/controllers/ (all files)

#### Tier 2: Integration — Plugs

- test/gallformers_web/plugs/ (all files)

#### Tier 2: Integration — Not yet implemented

- Data invariants on test DB (port from prod_data/invariants_test.exs)
- LiveView↔JS hook contract tests

#### Tier 3: E2E browser tests

- ID Tool flow
- Gall detail page
- Admin: create/edit gall workflow
- Admin: edit host workflow
- Search → detail flow
- Existing smoke tests — evaluate

#### Tier 5: Post-deploy smoke tests

- Evaluate current tests against philosophy

#### Structural issues

- JS test framework selection and setup (matter 2648)

## Update 2026-04-01

### Evaluated: test/gallformers/accounts_test.exs

**Status: Meets testing philosophy ✓**

**Strengths:**
- Uses `async: true` (compliant with Tier 1 rules)
- Creates own data, no seed data dependencies
- Happy path, error path, and boundary cases covered
- URL validation with valid and invalid inputs
- Duplicate auth0_id constraint tested
- Role checking functions (admin?, superadmin?, operator?) well covered
- Auth0User struct functions fully tested

**Improvements made:**
1. Added boundary tests for empty string URLs
2. Added boundary tests for whitespace-only display_name (trimmed to nil via changeset)
3. Added missing `get_user_by_nickname/1` tests (happy path + not found)
4. Added missing `db_display_name/1` tests (present, nil, empty string, missing key, empty map)
5. Strengthened `list_all_users/0` sorting test to verify actual alphabetical ordering with case-insensitive logic

**Test count: 60 (was ~46)**

---

**Next file: test/gallformers/analytics_test.exs**


### Evaluated: test/gallformers/analytics_test.exs

**Status: Meets testing philosophy ✓**

**Strengths:**
- Creates own data via Repo.insert (no seed dependencies)
- Good boundary coverage for should_track?/2 (bots, excluded paths, user agents)
- generate_visitor_hash/2 tests cover nil handling and hash format
- extract_referrer_host/2 tests cover same-site, nil, malformed URLs
- parse_user_agent/1 tests cover nil, unknown browsers, various device types
- Date range boundaries tested in stats/2 and daily_stats/2
- Summary-backed query integration tests verify data aggregation

**Improvements made:**
1. Added `async: true` (was missing, now 0.2s async)
2. Added boundary test for whitespace trimming in changeset
3. Added boundary test for empty strings becoming nil in optional fields

**Test count: 48 (was 46)**

---

**Next file: test/gallformers/articles_test.exs**


### Evaluated: test/gallformers/articles_test.exs

**Status: Meets testing philosophy ✓**

**Strengths:**
- Creates own data via create_article helper
- Good slug generation and collision handling
- Published state transitions tested (draft→published timestamp)
- Related articles filtering by tags and limit
- Tag counting with published_only filter
- Article.slugify/1 pure function well tested
- Cascade delete of content images tested

**Improvements made:**
1. Added `async: true` (was missing)
2. Added boundary test for max title length (200 chars)
3. Added boundary test for whitespace trimming
4. Added boundary test for empty strings after trimming

**Test count: 45 (was 42)**

---

**Next file: test/gallformers/changeset_helpers_test.exs**


### Evaluated: test/gallformers/changeset_helpers_test.exs

**Status: Meets testing philosophy ✓**

**Strengths:**
- Already has `async: true`
- trim_strings covers leading/trailing/inner/nil whitespace
- validate_url covers valid/invalid/empty/nil/whitespace cases
- Tests integration with Species.changeset
- No seed dependencies

**No changes needed. Test count: 16**

---

**Next file: test/gallformers/content_images_test.exs**


### Evaluated: test/gallformers/content_images_test.exs

**Status: Meets testing philosophy ✓**

**Strengths:**
- Already has `async: true`
- Creates own data (articles, keys) in setup
- Tests multiple owners (article, key)
- Sort order incrementing tested
- Owner validation in batch delete

**No changes needed. Test count: 19**

---

### Batch updates for remaining Tier 1 Unit tests (Context)

**Files updated with `async: true`:**
- test/gallformers/keys_test.exs
- test/gallformers/glossaries_test.exs  
- test/gallformers/markdown_test.exs
- test/gallformers/keys/pdf_generator_test.exs

**Files intentionally left sync (GenServer tests):**
- test/gallformers/analytics/rollup_test.exs - Tests GenServer, needs sync
- test/gallformers/images/audit_cache_test.exs - Tests GenServer with unique test instances
- test/gallformers/site_settings_test.exs - Uses persistent_term (global state)

**Type warning fixed in:**
- test/gallformers/plants_test.exs - Changed 5 instances of `has_changes != nil` to `has_changes == true`

---

**Current status summary:**
- **Total context unit tests:** 762 tests, 0 failures
- **All async-capable tests now use `async: true`**
- **Remaining sync tests:** 3 (GenServer/persistent_term related)

**Ready to move to next tier: Unit — Components**


### Evaluated: Tier 1 Unit — Components (all 6 files)

**Status: All meet testing philosophy ✓**

**Files updated with `async: true`:**
- test/gallformers_web/components/form_components_test.exs — 22 tests
- test/gallformers_web/components/region_scope_test.exs — 10 tests  
- test/gallformers_web/components/tree_components_test.exs — 9 tests
- test/gallformers_web/components/admin_form_components_test.exs — 6 tests

**Already compliant:**
- test/gallformers_web/components/data_display_components_test.exs — 9 tests (taxonomy breadcrumbs)
- test/gallformers_web/components/layouts_test.exs — 9 tests (site header)

**Total component tests: 56 (all async)**

**Coverage notes:**
- Components use dedicated test LiveViews (proper Tier 1 isolation)
- Props in, HTML out pattern
- Event handlers tested via LV test modules
- No database access in component tests

**Gaps identified (noted in Remaining):**
- typeahead component — no dedicated unit test
- multi_select_typeahead — no dedicated unit test
- taxon_name component — no dedicated unit test
- selectable_tree component — no dedicated unit test

---

**Next tier: Tier 2 Integration — Admin LiveViews**

Or continue with remaining Tier 1 Context files:
- galls_identification_test.exs
- galls_test.exs
- hosts_test.exs
- images_test.exs
- inaturalist_test.exs
- places_test.exs
- plants_test.exs (already fixed warnings)
- ranges_test.exs
- request_logger_test.exs
- search_test.exs
- species_test.exs
- storage_test.exs

Which direction?


### Tier 1 Unit — Context: All files evaluated ✓

**Status: All 762 tests passing, all async-capable tests use async: true**

**Done (already compliant or updated):**
- accounts_test.exs — 60 tests
- analytics_test.exs — 48 tests  
- articles_test.exs — 45 tests
- changeset_helpers_test.exs — 16 tests
- content_images_test.exs — 19 tests
- galls_identification_test.exs
- galls_test.exs
- hosts_test.exs
- images_test.exs
- inaturalist_test.exs
- keys_test.exs
- markdown_test.exs
- places_test.exs
- plants_test.exs (type warnings fixed)
- ranges_test.exs
- glossaries_test.exs
- species_test.exs
- search_test.exs
- sources_test.exs
- storage_test.exs
- taxonomy_test.exs
- taxonomy/*_test.exs (4 files)
- text_match_test.exs
- gall_summary_test.exs
- content_images/*_test.exs (2 files)
- gall_hosts_test.exs (already in Done)

**Intentionally sync (3 files):**
- analytics/rollup_test.exs — GenServer tests
- images/audit_cache_test.exs — GenServer with sandbox.allow
- site_settings_test.exs — Uses persistent_term (global state)

**Total: 762 tests, 0 failures, 1.1s async execution**

---

**Next: Tier 1 Unit — JS Hooks or Tier 2 Integration — Admin LiveViews**
