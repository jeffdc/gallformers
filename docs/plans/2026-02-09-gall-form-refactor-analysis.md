# Gall Form Refactor: Analysis Reference

> **Purpose**: Detailed function inventory, dependency map, and LiveView audit for `admin/gall_live/form.ex`.
> Load this file only when you need the full context for a specific extraction step.

## Summary Statistics

| Metric | Value |
|--------|-------|
| **Total lines** | 1,884 |
| **Public functions** | 47 (3 callbacks + 39 event handlers + 5 public helpers) |
| **Private functions** | ~35 |
| **Event handlers** | 39 (via `handle_event`) |
| **PubSub handlers** | 3 (via `handle_info`) |
| **Context dependencies** | 5 (Species, Galls, GallHosts, Taxonomy, Sources) |
| **Distinct context function calls** | 39 total across all contexts |
| **Render template lines** | ~485 (lines 1396-1883) |

## Function Inventory

### Group 1: Lifecycle & Routing (5 functions)

| Function | Lines | Cross-Domain? | Called From |
|----------|-------|---------------|------------|
| `mount/3` | 35-56 | Yes — Species, Galls, Taxonomy | Phoenix router |
| `handle_params/3` | 63-65 | No (delegates) | Phoenix router |
| `close_form/1` | 58-60 | No | FormHelpers (overrides default) |
| `render/1` | 1396-1883 | No | Phoenix LiveView |
| `handle_event("validate", ...)` (2 clauses) | 523-536 | No (Species changeset only) | Phoenix form |

### Group 2: Gall Search/Select/Create (4 event handlers)

| Function | Lines | Cross-Domain? | Called From |
|----------|-------|---------------|------------|
| `handle_event("search_gall", ...)` | 484-497 | Yes — Species.search_species | UI typeahead |
| `handle_event("select_gall", ...)` | 500-504 | No (navigates) | UI typeahead |
| `handle_event("create_gall", ...)` | 507-510 | No (delegates to init_new_gall_state) | UI typeahead |
| `handle_event("clear_gall", ...)` | 513-516 | No (navigates) | UI button |

### Group 3: State Initialization (10 private functions)

These are the "setup" functions that populate socket assigns when entering different modes.

| Function | Lines | Cross-Domain? | Notes |
|----------|-------|---------------|-------|
| `init_search_state/1` | 91-95 | No | Simple assign reset |
| `init_empty_gall_state/1` | 98-147 | No | **50 lines** — sets ~35 assigns to defaults |
| `init_new_gall_state/1` | 151-159 | Yes — Taxonomy | Dispatches to undescribed flow or normal form |
| `init_new_gall_form/3` | 176-228 | Yes — Species, Taxonomy | **53 lines** — mirrors init_empty_gall_state structure |
| `init_undescribed_gall_state/2` | 287-300 | Yes — Taxonomy | Dispatches after resolving name |
| `init_undescribed_gall_with_taxonomy/4` | 302-348 | Yes — Species | **47 lines** — mirrors init_new_gall_form structure |
| `load_gall_for_edit/3` | 374-437 | Yes — Galls, Species, GallHosts, Taxonomy | **64 lines** — heaviest, calls 6 context functions |
| `resolve_taxonomy_for_gall/2` | 231-282 | No (operates on data) | Gall-specific family filtering |
| `redirect_to_undescribed_flow/2` | 161-174 | No | Extracts description, navigates |
| `handle_load_error/3` | 467-477 | No | Two clauses for redirect vs stay |

**Key observation**: `init_empty_gall_state`, `init_new_gall_form`, `init_undescribed_gall_with_taxonomy`, and `load_gall_for_edit` all set ~30+ overlapping assigns. The init blocks are near-duplicates with slightly different data sources.

### Group 4: Alias Management (3 event handlers)

| Function | Lines | Cross-Domain? | Called From |
|----------|-------|---------------|------------|
| `handle_event("update_new_alias", ...)` (2 clauses) | 564-571 | No | UI input |
| `handle_event("add_alias", ...)` | 574-594 | No (DeferredChanges only) | UI button |
| `handle_event("remove_alias", ...)` | 597-606 | No (DeferredChanges only) | UI button |

### Group 5: Host Management (5 event handlers + 1 private)

| Function | Lines | Cross-Domain? | Called From |
|----------|-------|---------------|------------|
| `handle_event("search_hosts", ...)` | 613-626 | Yes — Species.search_species_by_name | UI typeahead |
| `handle_event("open_host_dropdown", ...)` | 629-631 | No | UI |
| `handle_event("close_host_dropdown", ...)` | 634-636 | No | UI |
| `handle_event("add_host", ...)` | 639-647 | No (DeferredChanges) | UI dropdown |
| `handle_event("remove_host", ...)` | 650-659 | No (DeferredChanges) | UI button |
| `add_host_to_pending/2` (private) | 1170-1190 | No (DeferredChanges) | add_host handler |

### Group 6: Gall Properties — Detachable/Undescribed/Family (5 event handlers + 1 private)

| Function | Lines | Cross-Domain? | Called From |
|----------|-------|---------------|------------|
| `handle_event("update_detachable", ...)` | 666-668 | No | UI select |
| `handle_event("toggle_undescribed", ...)` | 671-678 | No | UI checkbox |
| `handle_event("select_family", ...)` | 681-684 | No | UI select |
| `handle_event("select_family_from_disambiguation", ...)` | 687-716 | No | UI modal button |
| `compute_undescribed_lock/2` and `/3` | 1137-1168 | Yes — Taxonomy, Sources | Internal (3 call sites) |

### Group 7: Filter Management (5 event handlers + 3 private)

| Function | Lines | Cross-Domain? | Called From |
|----------|-------|---------------|------------|
| `handle_event("filter_search", ...)` | 719-725 | No | UI multi-select |
| `handle_event("open_filter_dropdown", ...)` | 728-731 | No | UI |
| `handle_event("close_filter_dropdown", ...)` | 734-736 | No | UI |
| `handle_event("add_filter", ...)` | 739-766 | No | UI dropdown |
| `handle_event("remove_filter", ...)` | 769-778 | No | UI chip |
| `empty_filter_values/0` | 439-451 | No | Internal (4 call sites) |
| `init_filter_search_state/0` | 453-465 | No | Internal (4 call sites) |
| `string_to_filter_type/1` | 1383-1389 | No | Internal (6 call sites) |

### Group 8: Reclassify Modal (12 event handlers + 4 private)

**This is the largest group — 16 functions, lines 784-1096.**

| Function | Lines | Cross-Domain? | Called From |
|----------|-------|---------------|------------|
| `handle_event("open_reclassify_modal", ...)` | 785-831 | Yes — Taxonomy, Species | UI button |
| `handle_event("close_reclassify_modal", ...)` | 834-839 | No | UI button |
| `handle_event("reclassify_search_family", ...)` | 842-854 | Yes — Taxonomy.search_families | UI typeahead |
| `handle_event("reclassify_select_family", ...)` | 857-874 | No | UI dropdown |
| `handle_event("reclassify_clear_family", ...)` | 877-887 | No | UI button |
| `handle_event("reclassify_search_genus", ...)` | 890-906 | Yes — Taxonomy.search_genera | UI typeahead |
| `handle_event("reclassify_select_genus", ...)` | 909-922 | No | UI dropdown |
| `handle_event("reclassify_clear_genus", ...)` | 925-931 | No | UI button |
| `handle_event("update_reclassify_epithet", ...)` | 934-951 | Yes — Species.find_species_with_alias | UI input |
| `handle_event("toggle_add_alias_on_rename", ...)` | 954-956 | No | UI checkbox |
| `handle_event("set_reclassify_alias_choice", ...)` | 959-962 | No | UI radio |
| `handle_event("do_reclassify", ...)` (2 clauses) | 965-1012 | Yes — via FormHelpers | UI button |
| `resolve_genus_id/2` (private) | 1032-1041 | Yes — Taxonomy.find_or_create_unknown_genus | do_reclassify |
| `compute_reclassify_name/2` (private) | 1043-1045 | No | do_reclassify |
| `apply_reclassify/5` (private) | 1047-1049 | Yes — FormHelpers.do_reclassify_and_rename | do_reclassify |
| `handle_reclassify_result/5` (3 clauses) | 1052-1096 | Yes — Taxonomy, Species | apply_reclassify |

### Group 9: Save Logic (6 private functions)

| Function | Lines | Cross-Domain? | Called From |
|----------|-------|---------------|------------|
| `save_gall/3` (:new clause) | 1192-1255 | Yes — Species, Galls, GallHosts, Taxonomy | handle_event("save") |
| `save_gall/3` (:edit clause) | 1257-1310 | Yes — Species, Galls, GallHosts | handle_event("save") |
| `save_gall_specific_data/2` | 1312-1324 | Yes — Galls, Species | save_gall(:edit) |
| `save_alias_changes/3` | 1326-1334 | Yes — Species | save_gall(:edit) |
| `save_host_changes/3` | 1336-1343 | Yes — GallHosts | save_gall(:edit) |
| `save_filter_changes/3` | 1346-1378 | Yes — Galls | save_gall(:new), save_gall_specific_data |

### Group 10: Delete & PubSub (4 functions)

| Function | Lines | Cross-Domain? | Called From |
|----------|-------|---------------|------------|
| `handle_event("delete", ...)` | 1019-1030 | Yes — Species.delete_species | UI button |
| `handle_info({:species_updated, ...})` | 1103-1110 | No (delegates to load_gall_for_edit) | PubSub |
| `handle_info({:species_deleted, ...})` | 1113-1123 | No | PubSub |
| `handle_info({:species_created, ...})` | 1126-1129 | No (no-op) | PubSub |

### Group 11: Miscellaneous Helpers (3 private functions)

| Function | Lines | Cross-Domain? | Called From |
|----------|-------|---------------|------------|
| `parse_int_param/1` (3 clauses) | 350-358 | No | init_undescribed_gall_state |
| `maybe_add_initial_host/2` (2 clauses) | 360-369 | No | init_undescribed_gall_with_taxonomy |
| `handle_form_event/3` | — | No | Delegated from FormHelpers macro |

## Dependency Map

### Outbound Dependencies (what this module calls into)

| Module | Functions Called | Count |
|--------|----------------|-------|
| `Gallformers.Species` | subscribe, search_species, search_species_by_name, change_species, create_species, update_species, delete_species, get_species!, get_species, get_aliases_for_species, create_alias_for_species, remove_alias_from_species, find_species_with_alias, has_former_undescribed_alias?, list_abundances, touch | 17 |
| `Gallformers.Taxonomy` | list_gall_families_for_select, lookup_taxonomy_for_new_species, placeholder_genus_name?, resolve_taxonomy_from_name, link_species_taxonomy, get_taxonomy_for_species, get_taxonomy, extract_epithet, search_families, search_genera, find_or_create_unknown_genus | 11 |
| `Gallformers.Galls` | get_all_filter_options, get_gall_for_admin_edit, create_gall_traits, update_gall_properties, get_gall_filter_values, add_filter_field_to_gall, remove_filter_field_from_gall | 7 |
| `Gallformers.GallHosts` | get_hosts_for_gall, add_host_to_gall, remove_host_from_gall | 3 |
| `Gallformers.Sources` | has_sources? | 1 |
| `Gallformers.Repo` | transaction, rollback | 2 |
| `GallformersWeb.Admin.FormHelpers` | init_form_state, mark_dirty, reset_dirty, handle_form_event, close_form, do_reclassify_and_rename, valid_species_name?, discard_confirm_modal | 8 (injected via `use`) |
| `GallformersWeb.Admin.DeferredChanges` | init, add_pending, remove_pending, exists?, compute_changes, refresh | 6 |
| `GallformersWeb.Admin.FormComponents` | alias_collision_warning, alias_editor, form_actions | 3 (imported) |
| `GallformersWeb.CoreComponents` | modal, icon, input, form, link, typeahead, multi_select_dropdown | ~7 (via `use GallformersWeb, :live_view`) |

### Inbound Dependencies (what calls into this module)

| Layer | File | How |
|-------|------|-----|
| **Router** | `lib/gallformers_web/router.ex:71,73` | `live "/galls/new", Admin.GallLive.Form, :new` and `live "/galls/:id", Admin.GallLive.Form, :edit` |

**This module has 0 inbound code references** — it's a leaf node. Only the router references it.
No other modules alias, import, or call functions from this module.

### Heaviest Outbound Consumers

1. **`Gallformers.Species`** — 17 distinct functions, called at ~25 call sites
2. **`Gallformers.Taxonomy`** — 11 distinct functions, called at ~15 call sites
3. **`Gallformers.Galls`** — 7 distinct functions, called at ~12 call sites

## LiveView Practices Audit

Since this is a LiveView (not a context module), auditing for business logic leakage, data loading patterns, and event handler complexity.

### Issue 1: Business Logic in LiveView — `resolve_taxonomy_for_gall/2` (lines 231-282)

**52 lines of gall-specific taxonomy resolution logic.** Filters possible families to non-plant families, handles disambiguation, decides whether genus is new. This is domain logic that belongs in the `Galls` context, not a LiveView.

**Fix**: Move to `Galls.resolve_taxonomy_for_gall/2` or `Taxonomy.resolve_taxonomy_for_gall/2`.

### Issue 2: Business Logic in LiveView — `compute_undescribed_lock/3` (lines 1141-1168)

**28 lines deciding whether the undescribed checkbox should be locked.** Calls into `Taxonomy.placeholder_genus_name?` and `Sources.has_sources?`. This is a domain rule about when a species can be marked as described.

**Fix**: Move to `Galls.compute_undescribed_lock(taxonomy, species_id)` returning `{locked?, reason}`.

### Issue 3: Business Logic in LiveView — `save_filter_changes/3` (lines 1346-1378)

**33 lines of filter diff-and-apply logic.** Computes set differences and issues individual add/remove calls. This is purely data persistence logic.

**Fix**: Move to `Galls.sync_filter_values(gall_id, original, current)`.

### Issue 4: Transaction Orchestration in LiveView — `save_gall/3` (lines 1192-1310)

**Two 60+ line functions** that orchestrate `Repo.transaction` with multiple context calls (create species, create gall_traits, link taxonomy, add hosts, add aliases, save filters, update properties). The LiveView is acting as a transaction coordinator.

**Fix**: Move to `Galls.create_gall_with_associations/1` and `Galls.update_gall_with_associations/2` that accept a params map with all nested data.

### Issue 5: Massive State Initialization Duplication (4 functions)

The following functions all set 30+ overlapping assigns to similar values:

| Function | Lines | Unique Params |
|----------|-------|---------------|
| `init_empty_gall_state/1` | 98-147 | None (all defaults) |
| `init_new_gall_form/3` | 176-228 | name, taxonomy, alias_collisions |
| `init_undescribed_gall_with_taxonomy/4` | 302-348 | name, taxonomy, host_id, undescribed=true |
| `load_gall_for_edit/3` | 374-437 | species, gall_data, aliases, hosts, taxonomy, filters |

~**200 lines** of near-duplicate assign chains. Each sets the same ~30 keys with slight variations.

**Fix**: Extract a common `build_gall_assigns/1` that takes a keyword list of overrides, with defaults matching `init_empty_gall_state`.

### Issue 6: Reclassify Modal is a Module-Within-a-Module (lines 784-1096)

**313 lines** (16% of the file) dedicated to the reclassify modal: 12 event handlers, 4 private helpers, ~15 reclassify-specific assigns. This is a self-contained feature that manages its own search state, selection state, and business logic.

**Fix**: Extract to a LiveComponent `GallformersWeb.Admin.GallLive.ReclassifyComponent` that:
- Manages its own assigns (family/genus search, epithet, alias options)
- Sends a single `{:reclassify_complete, result}` message back to the parent
- Could be shared with `host_live/form.ex` which has identical reclassify modal logic

### Issue 7: Direct Repo Usage (lines 1202, 1269)

The LiveView directly calls `Repo.transaction/1` and `Repo.rollback/1`. Context modules should own transaction boundaries.

**Fix**: Addressed by Issue 4 — move transaction into context.

### Issue 8: Inline Data Loading in `load_gall_for_edit/3` (lines 377-437)

Makes **6 sequential context calls** to load data:
1. `Galls.get_gall_for_admin_edit(species_id)` — gall traits + filters
2. `Species.get_species!(species_id)` — species record
3. `Species.get_aliases_for_species(species_id)` — aliases
4. `GallHosts.get_hosts_for_gall(species_id)` — hosts
5. `Taxonomy.get_taxonomy_for_species(species_id)` — taxonomy
6. (implicit) filter_values extracted from gall_data

**Fix**: `Galls.get_gall_for_admin_edit/1` should return all the data the form needs in one call, possibly via preloads. Or provide a dedicated `Galls.load_gall_for_form/1` that returns `{species, gall_data, aliases, hosts, taxonomy}`.

### Issue 9: `search_gall` Post-Filters in LiveView (line 488)

```elixir
Species.search_species(query, 10)
|> Enum.filter(&(&1.taxoncode == "gall"))
```

Searches all species then filters to galls in the LiveView. The search should accept a taxoncode filter.

**Fix**: Use `Species.search_species(query, 10, taxoncode: "gall")` or `Species.search_species_by_name(query, "gall", 10)` (which already exists and is used for host search at line 616).

## Test Coverage

### Test File: `test/gallformers_web/live/admin/gall_live/form_test.exs` (441 lines)

| Describe Block | Tests | What's Covered |
|----------------|-------|----------------|
| Mount and render - search mode | 3 | Page renders, intro text, disabled fieldset |
| Mount and render - deep link | 8 | Edit form, page title, rename button, quick links, public link, filter fields, invalid ID, non-existent ID |
| Gall search - search_gall event | 2 | Short query, valid query |
| Select existing gall | 1 | Selecting loads for edit |
| Clear gall | 1 | Clears and redirects |
| Alias management | 2 | Update alias name, empty alias error |
| Host search and management | 2 | Search hosts, add host |
| Filter management | 2 | Filter search, all filter types |
| Detachable | 1 | Marks form dirty |
| Undescribed toggle | 1 | Marks form dirty (with fixture setup) |
| Rename/Reclassify modal | 3 | Open modal, close modal, do_reclassify without genus |
| Cancel and discard | 2 | Clean cancel, dirty cancel |
| Access control | 1 | Requires admin session |
| **Total** | **29 tests** | |

### Untested Behaviors

| Behavior | Responsibility Group | Risk |
|----------|---------------------|------|
| `create_gall` event (new gall creation flow) | Group 2 | **High** — untested happy path |
| `save` event (both :new and :edit) | Group 9 | **High** — save transaction untested |
| `delete` event | Group 10 | **Medium** — delete flow untested |
| `add_alias` with valid name | Group 4 | Medium |
| `remove_alias` | Group 4 | Medium |
| `remove_host` | Group 5 | Medium |
| `add_filter` / `remove_filter` | Group 7 | Medium |
| `select_family_from_disambiguation` | Group 6 | Medium |
| Undescribed flow (`init_undescribed_gall_state`) | Group 3 | Medium |
| PubSub handlers (species_updated, species_deleted) | Group 10 | Low |
| `reclassify_search_family/genus` typeahead results | Group 8 | Low |
| `do_reclassify` happy path | Group 8 | **High** — complex multi-step operation |

### Test Quality Notes

- Tests use `require_gall()` and `require_host()` helpers that grab the first available record from the DB — tests depend on test seed data existing. If seeds change, tests may break silently.
- Several assertions use `or` patterns like `assert html =~ X or html =~ Y` which pass even when behavior is wrong (e.g., line 264: `assert html =~ host.name or html =~ "already" or html =~ "not found"` — any of three outcomes is "passing").
- No tests verify data persistence (e.g., save creates the record in the DB).
- No tests for the undescribed naming flow path (`:new` with `species_name` param).
- E2E tests for gall admin exist in `test/e2e/admin/admin_test.exs` but are commented out.

## Consolidation Opportunities

### 1. State Initialization Functions (4 → 1)

`init_empty_gall_state`, `init_new_gall_form`, `init_undescribed_gall_with_taxonomy`, and `load_gall_for_edit` share ~30 identical assigns. Extract a `reset_gall_assigns/2` that takes defaults and overrides.

**Estimated savings**: ~120 lines

### 2. Reclassify Modal Extraction (16 functions → 1 LiveComponent)

All 16 reclassify-related functions + 15 assigns → `ReclassifyComponent`. The host form has an **identical** reclassify modal (~250 lines duplicated).

**Duplicated assign initialization** (~12 assigns each):

| Assign Block | Gall Form | Host Form |
|--------------|-----------|-----------|
| Reclassify modal state | Lines 133-145 (1 copy) | Lines 75-83, 145-153, 736-743 (**3 copies**) |

**Duplicated event handlers** (identical logic in both):

| Event | Gall Form Lines | Host Form Lines |
|-------|----------------|----------------|
| `"open_reclassify_modal"` | 785-830 | 398-434 |
| `"close_reclassify_modal"` | 834-837 | 440-443 |
| `"reclassify_search_family"` | 842-853 | 448-459 |
| `"reclassify_select_family"` | 857-870 | 463-476 |
| `"reclassify_clear_family"` | 877-886 | 483-492 |
| `"reclassify_search_genus"` | 890-905 | 496-511 |
| `"reclassify_select_genus"` | 909-918 | 515-524 |
| `"reclassify_clear_genus"` | 925-930 | 531-536 |
| `"update_reclassify_epithet"` | 934-949 | 540-554 |
| `"set_reclassify_alias_choice"` | 959-961 | (not present — gall-only) |
| `"do_reclassify"` | 966-1004 | 565-595 |

**Duplicated private helpers**:

| Helper | Gall Form Lines | Host Form Lines |
|--------|----------------|----------------|
| `compute_reclassify_name/2` | 1043-1045 | (not present — inline) |
| `apply_reclassify/6` | 1047-1049 | 617-619 |
| `handle_reclassify_result/5` (3 clauses) | 1052-1093 | 622-661 |

**Shared (not duplicated)**:
- `do_reclassify_and_rename/5` in `form_helpers.ex:225` — called by both forms

**Notable differences**:
- Gall form has `set_reclassify_alias_choice` event + `reclassify_has_former_undescribed` / `reclassify_alias_choice` assigns (undescribed gall workflow)
- Host form initializes the reclassify assigns **three times** in different code paths (mount for new, mount for edit, reset after save) — copy-paste without cleanup
- Gall form has `compute_reclassify_name/2` as a named helper; host form computes inline

**Estimated savings**: ~313 lines from gall form, ~250 lines from host form, with a small callback for gall-specific undescribed alias logic

### 3. Save Transaction Extraction (6 → 2 context functions)

`save_gall(:new)`, `save_gall(:edit)`, `save_gall_specific_data`, `save_alias_changes`, `save_host_changes`, `save_filter_changes` → two context functions in `Galls`:
- `Galls.create_gall_with_associations(params)`
- `Galls.update_gall_with_associations(gall, params)`

**Estimated savings**: ~130 lines

### 4. `search_gall` Should Use Existing Taxoncode Filter

Line 487-488 searches all species then filters. `search_species_by_name/3` already accepts taxoncode (used at line 616 for hosts). Use it for gall search too.

**Estimated savings**: 3 lines, but eliminates a correctness issue (could return <10 gall results if non-galls fill the limit).

### 5. Dead/Redundant Code

| Item | Lines | Notes |
|------|-------|-------|
| `handle_info({:species_created, ...})` | 1126-1129 | No-op handler — only exists to avoid "no clause matching" warning |
| `handle_event("validate", _params, socket)` | 533-536 | Catch-all for non-form validate events — may be unnecessary |
| Two clauses of `handle_event("update_new_alias", ...)` | 564-571 | Identical logic, different param destructuring — merge into one |

### 6. Business Logic That Doesn't Belong Here

| Function | Lines | Should Move To |
|----------|-------|----------------|
| `resolve_taxonomy_for_gall/2` | 231-282 | `Galls` or `Taxonomy` context |
| `compute_undescribed_lock/3` | 1137-1168 | `Galls` context |
| `save_filter_changes/3` | 1346-1378 | `Galls` context |
| `resolve_genus_id/2` | 1032-1041 | `Taxonomy` context |
| `compute_reclassify_name/2` | 1043-1045 | `Taxonomy` context (trivial, but couples LiveView to naming logic) |
