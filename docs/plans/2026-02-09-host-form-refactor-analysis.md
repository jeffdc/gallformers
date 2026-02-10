# Host Form Refactor: Analysis Reference

> **Purpose**: Detailed function inventory, dependency map, and LiveView audit for `admin/host_live/form.ex`.
> **Cross-reference**: `docs/plans/2026-02-09-gall-form-refactor-analysis.md` — the gall form analysis.
> These two files share massive amounts of duplicated code and should be refactored together.

## Summary Statistics

| Metric | Value |
|--------|-------|
| **Total lines** | 1,296 |
| **Public functions** | 33 (3 callbacks + 27 event handlers + 3 public helpers) |
| **Private functions** | ~20 |
| **Event handlers** | 27 (via `handle_event`) |
| **PubSub handlers** | 0 (does not subscribe!) |
| **Context dependencies** | 6 (Species, Plants, Taxonomy, Places, Ranges, Repo) |
| **Render template lines** | ~360 (lines 934-1296) |

## Function Inventory

### Group 1: Lifecycle & Routing (5 functions)

| Function | Lines | Cross-Domain? | Called From |
|----------|-------|---------------|------------|
| `mount/3` | 22-38 | Yes — Species, Places, Taxonomy | Phoenix router |
| `handle_params/3` | 45-47 | No (delegates) | Phoenix router |
| `close_form/1` | 40-42 | No | FormHelpers (overrides default) |
| `render/1` | 934-1296 | No | Phoenix LiveView |
| `handle_event("validate", ...)` (2 clauses) | 179-192 | No (Plants changeset only) | Phoenix form |

### Group 2: Host Search/Select/Create (4 event handlers)

| Function | Lines | Cross-Domain? | Called From |
|----------|-------|---------------|------------|
| `handle_event("search_host", ...)` | 221-234 | Yes — Species.search_species | UI typeahead |
| `handle_event("select_host", ...)` | 237-241 | No (navigates) | UI typeahead |
| `handle_event("create_host", ...)` | 244-247 | No (delegates) | UI typeahead |
| `handle_event("clear_host", ...)` | 250-253 | No (navigates) | UI button |

### Group 3: State Initialization (4 private functions)

| Function | Lines | Cross-Domain? | Notes |
|----------|-------|---------------|-------|
| `apply_action(:new, ...)` | 49-87 | No | **39 lines** — sets ~25 assigns to defaults |
| `apply_action(:edit, ...)` | 89-107 | Yes — Plants | Validates taxoncode, delegates |
| `load_host_for_edit/2` | 109-157 | Yes — Plants, Taxonomy, Ranges | **49 lines** — mirrors apply_action(:new) structure |
| `init_new_host_state/2` | 689-747 | Yes — Plants, Taxonomy, Species | **59 lines** — mirrors both above |

**Key observation**: Same problem as gall form — `apply_action(:new)`, `load_host_for_edit`, and `init_new_host_state` all set ~25 overlapping assigns with slight variations.

### Group 4: Alias Management (4 event handlers)

| Function | Lines | Cross-Domain? | Called From |
|----------|-------|---------------|------------|
| `handle_event("update_new_alias", ...)` (2 clauses) | 321-330 | No | UI input |
| `handle_event("add_alias", ...)` | 333-353 | No (DeferredChanges only) | UI button |
| `handle_event("remove_alias", ...)` | 356-365 | No (DeferredChanges only) | UI button |

### Group 5: Taxonomy Selection — Family/Section/Disambiguation (3 event handlers)

| Function | Lines | Cross-Domain? | Called From |
|----------|-------|---------------|------------|
| `handle_event("select_family", ...)` | 256-273 | Yes — Taxonomy.list_sections_for_family | UI select |
| `handle_event("select_section", ...)` | 276-279 | No | UI select |
| `handle_event("select_family_from_disambiguation", ...)` | 282-316 | Yes — Taxonomy.list_sections_for_genus | UI modal |

### Group 6: Range/Place Management (4 event handlers + 2 private)

| Function | Lines | Cross-Domain? | Called From |
|----------|-------|---------------|------------|
| `handle_event("toggle_region", ...)` | 370-372 | No | UI map click |
| `handle_event("select_all_places", ...)` | 375-383 | No | UI button |
| `handle_event("deselect_all_places", ...)` | 386-393 | No | UI button |
| `toggle_region/2` (private, 2 clauses) | 671-682 | No | toggle_region handler |
| `toggle_place_code/2` (private) | 684-686 | No | toggle_region |

### Group 7: Reclassify Modal (11 event handlers + 3 private)

**This is the largest group — 14 functions, lines 397-669.**

| Function | Lines | Cross-Domain? | Called From |
|----------|-------|---------------|------------|
| `handle_event("open_reclassify_modal", ...)` | 398-437 | Yes — Taxonomy | UI button |
| `handle_event("close_reclassify_modal", ...)` | 440-445 | No | UI button |
| `handle_event("reclassify_search_family", ...)` | 448-460 | Yes — Taxonomy.search_families | UI typeahead |
| `handle_event("reclassify_select_family", ...)` | 463-480 | No | UI dropdown |
| `handle_event("reclassify_clear_family", ...)` | 483-493 | No | UI button |
| `handle_event("reclassify_search_genus", ...)` | 496-512 | Yes — Taxonomy.search_genera | UI typeahead |
| `handle_event("reclassify_select_genus", ...)` | 515-528 | No | UI dropdown |
| `handle_event("reclassify_clear_genus", ...)` | 531-537 | No | UI button |
| `handle_event("update_reclassify_epithet", ...)` | 540-556 | Yes — Species.find_species_with_alias | UI input |
| `handle_event("toggle_add_alias_on_rename", ...)` | 559-561 | No | UI checkbox |
| `handle_event("do_reclassify", ...)` (2 clauses) | 564-601 | Yes — via FormHelpers | UI button |
| `apply_reclassify/6` (private) | 617-619 | Yes — FormHelpers.do_reclassify_and_rename | do_reclassify |
| `handle_reclassify_result/5` (3 clauses) | 622-669 | Yes — Taxonomy, Plants | apply_reclassify |

### Group 8: Save Logic (4 private functions)

| Function | Lines | Cross-Domain? | Called From |
|----------|-------|---------------|------------|
| `save_host/3` (:new clause) | 803-846 | Yes — Plants, Taxonomy, Repo | handle_event("save") |
| `save_host/3` (:edit clause) | 848-902 | Yes — Plants, Ranges, Taxonomy, Repo | handle_event("save") |
| `save_alias_changes/3` | 905-915 | Yes — Plants | save_host(:edit) |
| `save_place_changes/4` | 918-932 | Yes — Ranges | save_host(:edit) |

### Group 9: Delete & Misc (3 functions)

| Function | Lines | Cross-Domain? | Called From |
|----------|-------|---------------|------------|
| `handle_event("delete", ...)` | 604-615 | Yes — Plants.delete_host | UI button |
| `maybe_update_section/1` | 160-174 | Yes — Taxonomy.update_genus_parent | save_host(:edit) |
| `resolve_taxonomy_for_host/2` | 750-801 | No (operates on data) | init_new_host_state |

## Dependency Map

### Outbound Dependencies

| Module | Functions Called | Count |
|--------|----------------|-------|
| `Gallformers.Plants` | get_host_species, change_host, create_host, update_host, delete_host, get_aliases_for_host_full, create_alias_for_host, remove_alias_from_host | 8 |
| `Gallformers.Taxonomy` | list_plant_families_for_select, lookup_taxonomy_for_new_species, get_taxonomy_for_species, get_taxonomy, extract_epithet, search_families, search_genera, list_sections_for_family, list_sections_for_genus, link_species_taxonomy, update_genus_parent | 11 |
| `Gallformers.Species` | list_abundances, search_species, find_species_with_alias | 3 |
| `Gallformers.Places` | list_places | 1 |
| `Gallformers.Ranges` | get_places_for_host, update_host_places | 2 |
| `Gallformers.Repo` | transaction, rollback | 2 |
| `GallformersWeb.Admin.FormHelpers` | (injected via `use`) | 8 |
| `GallformersWeb.Admin.DeferredChanges` | init, add_pending, remove_pending, exists?, compute_changes, refresh | 6 |
| `GallformersWeb.Admin.FormComponents` | alias_collision_warning, alias_editor, form_actions | 3 |

### Inbound Dependencies

| Layer | File | How |
|-------|------|-----|
| **Router** | `lib/gallformers_web/router.ex` | `live "/hosts/new"` and `live "/hosts/:id"` |

**This module has 0 inbound code references** — leaf node like the gall form.

## LiveView Practices Audit

### Issue 1: Business Logic in LiveView — `resolve_taxonomy_for_host/2` (lines 750-801)

**52 lines** of host-specific taxonomy resolution logic. Filters possible families to plant families, handles disambiguation. Structurally **identical** to `resolve_taxonomy_for_gall/2` in the gall form — the only difference is filtering to plant families instead of gall families.

**Fix**: Extract to `Taxonomy.resolve_taxonomy_for_species/3` taking a family_ids filter set, or to `Plants.resolve_taxonomy_for_host/2`.

### Issue 2: Transaction Orchestration in LiveView — `save_host/3` (lines 803-902)

Two ~45 line functions orchestrating `Repo.transaction` with multiple context calls. Same pattern as gall form.

**Fix**: Move to `Plants.create_host_with_associations/1` and `Plants.update_host_with_associations/2`.

### Issue 3: `search_host` Post-Filters in LiveView (line 224-225)

```elixir
Species.search_species(query, 10)
|> Enum.filter(&(&1.taxoncode == "plant"))
```

Identical issue to gall form — searches all species then filters. `search_species_by_name/3` already accepts taxoncode.

**Fix**: Use `Species.search_species_by_name(query, "plant", 10)`.

### Issue 4: State Initialization Duplication (3 functions)

Same problem as gall form — `apply_action(:new)`, `load_host_for_edit`, and `init_new_host_state` set ~25 overlapping assigns.

**Estimated savings**: ~60 lines

### Issue 5: No PubSub Subscription (unlike gall form)

The gall form subscribes to `Species.subscribe()` and handles `species_updated`/`species_deleted` events. The host form does not. If two admins edit the same host concurrently, they won't see each other's changes or deletions.

**Fix**: Add PubSub subscription for consistency.

### Issue 6: `maybe_update_section/1` Is Business Logic (lines 160-174)

Decides whether to update a genus's parent taxonomy based on section changes. This is domain logic about taxonomy hierarchy that belongs in a context.

**Fix**: Move to `Taxonomy.maybe_update_genus_section/3` or handle within `Plants.update_host_with_associations`.

### Issue 7: Direct Repo Usage (lines 814, 856)

Same as gall form — LiveView directly uses `Repo.transaction/1`.

## Test Coverage

### Test File: `test/gallformers_web/live/admin/host_live/form_test.exs` (483 lines)

| Describe Block | Tests | What's Covered |
|----------------|-------|----------------|
| Mount and render - new mode | 5 | Page renders, title, disabled form, back link, typeahead search |
| Mount and render - edit mode | 9 | Edit form, title, rename button, quick links, public link, range map, aliases, invalid ID, non-existent ID |
| Form validation | 2 | Validate in edit mode, validate in new mode |
| Alias management - update_new_alias | 2 | Name field change, type field change |
| Add and remove alias | 1 | Empty alias error |
| Range/place management | 7 | Toggle in search/edit mode, invalid code, select all in search/edit, deselect all in search/edit |
| Rename/Reclassify modal | 5 | Open, close, toggle alias checkbox, do without genus, update epithet |
| Cancel and discard | 2 | Clean cancel, dirty cancel |
| UI elements | 5 | Legend, map buttons, data complete, genus field, family field, section field |
| Access control | 1 | Requires admin session |
| **Total** | **39 tests** | |

### Untested Behaviors

| Behavior | Risk |
|----------|------|
| `save` event (both :new and :edit) | **High** — save transaction untested |
| `delete` event | **Medium** — delete flow untested |
| `add_alias` with valid name | Medium |
| `remove_alias` | Medium |
| `do_reclassify` happy path | **High** — complex multi-step operation |
| `reclassify_search_family/genus` typeahead results | Low |
| `select_family` with section loading | Medium |
| `select_family_from_disambiguation` | Medium |
| Concurrent edit (no PubSub) | Low |

### Test Quality Notes

Same patterns as gall form tests:
- Weak `or`-based assertions (e.g., line 82: `assert html =~ "host-picker" or html =~ "Quercus"`)
- No tests verify data persistence after save
- `require_host()` depends on test seeds existing
- Invalid host ID test uses `assert_raise ArgumentError` (line 158) — this is a crash, not a graceful redirect. Gall form handles this case with `Integer.parse` and a redirect.

---

## Cross-Form Duplication Analysis: Gall Form vs Host Form

This is the core finding that motivates tackling both forms together.

### Identical Code Patterns

#### 1. Reclassify Modal (~270 lines duplicated)

Already documented in the gall form analysis update. Summary:
- **10 event handlers** are line-for-line identical (different only in variable names: `@gall` vs `@host`)
- **3 private helpers** are identical in structure
- **~12 assigns** for reclassify state initialized in 3 places in host form, 2 in gall form
- Only gall form has `set_reclassify_alias_choice` (undescribed gall workflow) — this is the only real difference

**Extraction target**: `ReclassifyComponent` LiveComponent with callback for entity-specific post-reclassify behavior.

#### 2. Alias Management (~45 lines duplicated)

| Event | Gall Form Lines | Host Form Lines | Identical? |
|-------|----------------|----------------|------------|
| `update_new_alias` (2 clauses) | 564-571 | 321-330 | **Yes** |
| `add_alias` | 574-594 | 333-353 | **Yes** |
| `remove_alias` | 597-606 | 356-365 | **Yes** |

All three events are identical — they operate on `DeferredChanges` with the same field names (`:aliases`, `:name`, `:type`).

**Extraction target**: Either a shared module function or a LiveComponent for alias editing.

#### 3. Entity Search/Select/Create Typeahead (~40 lines duplicated)

| Event | Gall Form Lines | Host Form Lines | Identical? |
|-------|----------------|----------------|------------|
| `search_*` | 484-497 | 221-234 | **Same structure**, different taxoncode filter |
| `select_*` | 500-504 | 237-241 | **Same structure**, different route |
| `create_*` | 507-510 | 244-247 | **Same structure**, different init function |
| `clear_*` | 513-516 | 250-253 | **Yes** (both call close_form) |

The pattern is: search species by name → filter by taxoncode → select navigates to edit URL → create calls init function. The taxoncode, route, and init function are the only differences.

**Extraction target**: Could share via a parameterized helper in FormHelpers, but the savings are small (~15 lines). Lower priority.

#### 4. Taxonomy Resolution (~52 lines duplicated)

`resolve_taxonomy_for_gall/2` (gall form 231-282) and `resolve_taxonomy_for_host/2` (host form 750-801) are **structurally identical**. The only difference:
- Gall form: filters to `gall_family_ids`
- Host form: filters to `plant_family_ids`
- Host form returns 5-tuple (includes `section_id`), gall form returns 4-tuple

**Extraction target**: `Taxonomy.resolve_taxonomy_for_species/3` with a family filter.

#### 5. Genus Disambiguation Modal Template (~40 lines duplicated)

The `<.modal>` block for genus disambiguation is identical in both render functions:
- Gall form: lines 1842-1879
- Host form: lines 1254-1292

Only differences: `"clear_gall"` vs `"clear_host"` event, "gall-forming" vs "plant" wording.

**Extraction target**: A shared component `genus_disambiguation_modal/1`.

#### 6. Form Structure Template (~50 lines duplicated)

The Genus/Family row in both forms is nearly identical:
- Gall form: lines 1514-1559
- Host form: lines 1050-1095

Same disabled genus input, same family select/display logic, same validation messages.

#### 7. `save_alias_changes/3` (~10 lines duplicated)

Identical function in both files:
- Gall form: lines 1326-1334 (calls `Species.remove_alias_from_species` / `Species.create_alias_for_species`)
- Host form: lines 905-915 (calls `Plants.remove_alias_from_host` / `Plants.create_alias_for_host`)

The alias CRUD functions in Species vs Plants are themselves duplicates (Plants delegates to Species internally or uses the same pattern).

### Unique to Gall Form (not in Host Form)

| Feature | Lines | Notes |
|---------|-------|-------|
| Filter management (9 filter types) | 661-778, 1346-1389 | Colors, shapes, textures, etc. |
| Detachable property | 666-668 | Select dropdown |
| Undescribed toggle + lock logic | 671-678, 1137-1168 | Business rule enforcement |
| Host picker (multi-select) | 613-659 | Adding/removing host associations |
| PubSub subscription + handlers | 38, 1102-1129 | Real-time updates |
| Undescribed naming flow | 161-174, 284-369 | Redirect to guided flow |
| `reclassify_alias_choice` / `has_former_undescribed` | 959-962, 813-815 | Gall-specific reclassify options |

### Unique to Host Form (not in Gall Form)

| Feature | Lines | Notes |
|---------|-------|-------|
| Range/place management (map) | 370-393, 671-686, 918-932 | Toggle regions, select/deselect all |
| Section selection | 276-279, 1097-1132 | Section dropdown under family |
| `maybe_update_section/1` | 160-174 | Updates genus parent on section change |
| Info tooltip on name field | 980-991, 1025-1037 | Binomial nomenclature help |

### Quantified Duplication Summary

| Duplicated Pattern | Gall Lines | Host Lines | Shared After Extract |
|--------------------|-----------|-----------|---------------------|
| Reclassify modal (events + assigns + helpers) | ~313 | ~273 | ~100 (component) |
| Alias management (3 events) | ~45 | ~45 | ~45 (shared module) |
| Taxonomy resolution | ~52 | ~52 | ~55 (context function) |
| Genus disambiguation modal (template) | ~38 | ~39 | ~40 (component) |
| Genus/Family row (template) | ~45 | ~46 | ~46 (component) |
| State init duplication (within each file) | ~200 | ~150 | ~50 each (helper) |
| Save alias changes | ~9 | ~11 | ~12 (context function) |
| Entity search post-filter | ~14 | ~14 | ~5 each (use existing fn) |
| **Total duplicated** | **~716** | **~630** | **~353** |

**Net reduction estimate**: ~1,000 lines removed across both files (from combined ~3,180 to ~2,180), with shared infrastructure of ~350 lines.
