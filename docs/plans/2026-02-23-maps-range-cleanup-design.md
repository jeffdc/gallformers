# Maps and Range System Cleanup Design

**Matter**: b99b — Maps and range system assessment
**Branch**: maps-rework (fix before merge)
**Scope**: All 62 findings from the assessment, minus JS test framework setup (separate matter)

## Context

The maps-rework branch adds PMTiles-based range maps, precision-tagged host ranges (exact vs country-level), gall range exclusions, and admin drill-down panels. An assessment found 8 bugs, 5 design inconsistencies, 12 test gaps, 5 UI/UX issues, and 32 code quality problems.

The core structural issue: precision expansion (country → leaf codes) is implemented in three places — `Ranges.split_by_precision`, `GallHostLive.assign_range_data`, and `HostLive.Form.compute_map_range`. These can drift and have already produced bugs. The fix is making the Ranges context the single source of truth.

## Decisions Made

- **Fix everything before merging maps-rework** — no shipping known bugs or code smells
- **JS test framework** — valuable but separate scoped effort (new matter)
- **Bulk operations** — belong in drill-down panels (country level), not page level. Restore Select All / Deselect All to ExclusionDrillDown
- **Drill-down components** — extract a shared shell component since they're converging
- **Precision expansion** — single source of truth in Ranges context
- **Save logic** — move GallHostLive save transaction to context; fix Plants.save_place_changes interface
- **UI polish** — include all items (hemisphere bounds, fitToRange, empty state, heights)
- **Legend** — extract as a reusable component

## Phase 1: Ranges Context Cleanup

The context layer is the root of most problems. Fix it first, everything above gets simpler.

### DisplayRange struct (#60)

Create `Gallformers.Ranges.DisplayRange` struct:

```elixir
defstruct [:in_range, :inherited_range, :excluded_range]
# in_range: [String.t()] — exact leaf codes
# inherited_range: [String.t()] — expanded from country-level
# excluded_range: [String.t()] — explicitly excluded (galls only)
```

Return this from `get_display_range_for_gall/1` and `get_display_range_for_host/1`.

### Batch precision expansion (#31, #41, #47)

Replace the per-country `split_by_precision` with a batch version:

1. Partition ranges into exact and country
2. Collect all country `place_id`s
3. One call to get all leaf descendant IDs
4. One query to get all leaf codes
5. Return `{exact_codes, inherited_codes}` using MapSet operations

Make this a public function so admin pages can call it instead of reimplementing.

### Use Place schema in queries (#32, #33)

Replace all `from(p in "place", ...)` joins with `from(p in Place, ...)`. The Place schema exists. Raw table strings bypass type casting and make the code harder to trace. Same for `get_hosts_for_place` which uses `"alias_species"` and `"alias"` — check if schemas exist, use them if so.

### Merge duplicate helpers (#34)

`normalize_place_entries` and `normalize_exclusion_entries` are identical. Replace with a single `normalize_entries/2`.

### Fix return values (#35)

`add_place_to_host` and `remove_place_from_host` should propagate the actual `Repo.insert`/`Repo.delete_all` result instead of ignoring it. Return `{:ok, HostRange}` or `{:error, changeset}`.

### Fix TOCTOU in toggles (#36)

`toggle_place_for_host` and `toggle_exclusion_for_gall` do check-then-act. Wrap each in `Repo.transaction` or use upsert patterns.

### Use MapSet over list subtraction (#37)

Replace `--` in `get_display_range_for_gall` with `MapSet.difference`. Remove redundant `Enum.uniq` calls where input is already deduplicated by `distinct: true`.

### Remove nested transaction (#38)

`set_range_exclusions_for_gall` wraps in `Repo.transaction` but is also called inside the GallHostLive save transaction. Remove the inner transaction — make the function assume it's called within a transaction (or check `Repo.in_transaction?`).

### Move save logic to contexts (#44, #49)

**GallHostLive save** → new context function, likely `GallHosts.save_gall_host_mappings/3` that accepts `{gall_id, hosts_to_add, hosts_to_remove, excluded_place_ids}` and owns the transaction.

**Plants.save_place_changes** → change interface to accept `{host_id, [{place_id, precision}]}`. The LiveView does code→ID conversion before calling. The context function just calls `Ranges.update_host_places`.

## Phase 2: LiveView Cleanup

With the context cleaned up, simplify the LiveViews.

### Fix bug #7

Change `toggle_region` handler to pass `host_places_raw` instead of `host_places`.

### Extract toggle_exclusion helper (#40)

The identical exclusion toggle logic in `toggle_region`, `toggle_country` (leaf branch), and `handle_info` for ExclusionDrillDown becomes a single `toggle_exclusion(socket, place_id)` helper.

### Replace local expansion with context calls (#11)

`GallHostLive.assign_range_data` and `HostLive.Form.compute_map_range` both reimplement precision expansion. Replace with calls to the Ranges context's batch expansion (from Phase 1). Admin pages receive `DisplayRange` structs just like public pages.

For the admin case where changes are deferred (not yet saved), the context function needs to accept a list of host_species_ids + excluded_place_ids rather than reading from the DB. Add a function like `Ranges.compute_display_range/2` that takes `{host_ranges, exclusions}` as input.

### Cache lookup maps (#42, #48, #62)

Compute `place_by_code` and `place_by_id` maps once in `mount` from `all_places`. Store as assigns. All code that needs to resolve codes or IDs uses these maps instead of linear scans or DB queries.

### Eliminate ID↔code bouncing (#43, #46)

`recompute_host_places_and_range` converts IDs→codes→filter→codes→IDs. Work in one space (IDs) throughout. The cached lookup maps make this straightforward.

### Use range_map component in GallHostLive (#9, #10, #45)

Replace the raw `<div phx-hook="RangeMap">` with the `<.range_map>` component. The component already supports all needed attrs. The `push_event("range-update", ...)` pattern continues to work alongside the component since the hook handles both update mechanisms.

### Consistent list usage (#61)

Remove unnecessary `MapSet.new` → `MapSet.to_list` round-trips in `GallLive` and `HostLive`. The context returns lists, the component accepts lists — pass them through.

### Small fixes

- Fix `toggle_place_code` to prepend (#50)
- Add `@impl true` to `handle_info` callbacks (#39)

## Phase 3: Components — Drill-downs and Legend

### Extract shared DrillDown shell (#12)

Create a `DrillDown` function component (not LiveComponent) that renders:
- Slide-in panel with transition
- Header with country name and close button
- Optional help text slot
- Optional bulk action buttons slot
- Subdivision list with checkboxes (configurable checked/color logic via slots or callbacks)

`ExclusionDrillDown` and `CountryDrillDown` become thin wrappers that provide their specific checkbox semantics.

### Restore bulk ops in ExclusionDrillDown (#13)

Add Select All / Deselect All back. "Select all" = include all (remove exclusions). "Deselect all" = exclude all. Wire through to parent via the same `notify_parent` pattern.

### Precompute excluded codes (#51)

In `ExclusionDrillDown.update/2`, build a `MapSet` of excluded codes from `excluded_place_ids` + `all_places`. Use it in the template instead of calling `excluded?/3` per subdivision per attribute.

### Consistent notify_parent (#52)

Remove the unused `socket` parameter from `CountryDrillDown.notify_parent`. Both components use `notify_parent(message)`.

### Filter CountryDrillDown subdivisions (#53)

CountryDrillDown currently shows ALL subdivisions. For consistency with ExclusionDrillDown, consider filtering. However, the semantics differ — CountryDrillDown is for *adding* places to range, so showing all subdivisions is arguably correct (you're choosing which to add). Leave as-is but add a comment explaining the deliberate difference.

### Explicit assigns in update/2 (#54)

Replace `Map.take` in ExclusionDrillDown's catch-all `update/2` with explicit pattern matching.

### Legend component (#30)

Extract a `<.range_map_legend>` component with a `mode` attr:
- `:public` — Documented (green), Country-level (light green)
- `:host_admin` — Documented (green), Country-level (light green), Out of Range (white)
- `:gall_admin` — Gall & Host (green), Country-level (light green), Host Only (red), Neither (white)

Colors defined once, matching the JS `COLORS` constants. All four pages use the component.

## Phase 4: JS Hook Improvements

### Fix country hover tooltip (#8)

Add `excludedRange` check to the country hover handler. If `excludedRange.has(code)`, show "Excluded" status.

### Compute effective sets once (#55)

Add a `computeEffectiveSets()` method that builds `effectiveInRange` and `effectiveInherited` once. Call it from `updateChoropleth` and pass the results to `buildFillExpression`. Saves rebuilding the sets twice per update.

### Server-side bounds (#56, #27)

Add `data-bounds` attribute to the component: `[[minLng, minLat], [maxLng, maxLat]]`. Compute in the LiveView from the range codes (the Places context can provide bounding boxes). `fitToRange` reads this attribute first; falls back to `querySourceFeatures` if not provided. This eliminates the loaded-tiles dependency.

### Single-pass zoomToCountry (#57)

Combine the country and subdivision feature scans into one loop over all source features.

### Error handling for missing PMTiles (#58)

Add an error handler on the map's `error` event. If the tile source fails to load, show a user-facing message in the map container (e.g., "Map data unavailable").

### Fullscreen hint CSS (#59)

Replace inline `style.cssText` with Tailwind utility classes applied via `className`.

### Empty state (#28)

When `inRange.size === 0 && inheritedRange.size === 0` and the map has loaded, show an overlay: "No range data available." Add a `data-empty-text` attribute so the text is configurable from the server.

### Standardize map heights (#29)

Pick a standard: `min-h-[400px]` as the component default. Admin pages can override to `min-h-[500px]` if they need more space. Remove the `h-[60vh]` from the place page — use the same default. Define these as component size variants if warranted.

### Hemisphere bounds (#26)

Make `maxBounds` configurable via a `data-max-bounds` attribute. Default to current Western Hemisphere bounds. This prepares for Eastern Hemisphere expansion without changing current behavior.

## Phase 5: Tests

### Test fixtures (#22)

Add gall_range_exclusion rows to `test_seeds.sql`. Add a gall with both exact host ranges and exclusions so tests can exercise the full display range pipeline.

### Context tests

- `get_display_range_for_gall/1` (#14) — test exact + inherited + excluded, verify exclusions subtracted from both
- `get_display_range_for_host/1` (#16) — test exact + inherited
- `split_by_precision` via display functions (#15) — test country expansion produces correct leaf codes
- `toggle_exclusion_for_gall/2` (#17) — test add and remove
- `get_places_for_gall/1`, `get_places_for_galls/1` (#20) — test host union
- `toggle_place_for_host/2`, `remove_place_from_host/2` (#21)

### Component tests

- ExclusionDrillDown (#18) — open/close, toggle, bulk ops, parent notification
- CountryDrillDown (#19) — open/close, country-level toggle, subdivision toggle, select all/deselect all

### Admin page tests

- Range toggle with state assertions (#24) — verify actual range data changes, not just "page didn't crash"
- Drill-down workflow (#25) — click country → panel opens → toggle subdivisions → close → verify state

## Out of Scope

- **JS test framework setup** (#23) — separate matter, separate branch
- **JS perf for fitToRange feature iteration** (#56 partial) — addressed by server-side bounds
