---
status: done
created: 2026-02-23
updated: 2026-02-23
epic: geo-expansion
docs: [docs/plans/completed/2026-02-23-maps-range-cleanup-design.md]
relates: [8900, 2648]
blocks: [8900]
---

# Maps and range system assessment

Assessment of the maps-rework branch: UI, range computation, admin workflows, and test coverage.

## Bugs Found and Fixed (on branch, uncommitted)

These were discovered in an earlier session and have uncommitted fixes:

1. **`Places.list_places()` vs `list_all_places()`** — `list_places()` only returns leaf places (states/provinces and leaf countries without subdivisions). The gall-host admin page and host form both used `list_places()`, causing country codes like "US" to silently disappear from the `all_places` lookup map. Country-level host ranges were invisible. **Fix**: Both pages now call `list_all_places()`.

2. **`split_by_precision` expects `place_id`** — The shared helper accesses `range.place_id` for country-level expansion, but `get_places_for_host_with_precision` didn't include it in its select. Only crashes when a host has country-level precision (not exact), so it went unnoticed. **Fix**: Added `place_id: p.id` to the select.

3. **`get_display_range_for_gall` didn't subtract exclusions from exact codes** — Only inherited codes had exclusions subtracted. Excluding a state on the admin page saved correctly but the public page still showed it as in-range. **Fix**: Now subtracts exclusions from both exact and inherited.

4. **ExclusionDrillDown checkbox semantics were inverted** — Checked = excluded, which is confusing. Users expect checked = in range. **Fix**: Inverted to checked = in range (unchecked = excluded). Updated colors (green checkboxes instead of red) and help text.

5. **ExclusionDrillDown showed non-host subdivisions** — The panel listed ALL subdivisions for a country, including ones where the host doesn't exist. Curators could "exclude" places that weren't in range anyway. **Fix**: Now filters to only show subdivisions in the host range.

6. **JS click handler re-opened drill-down on subdivision clicks** — When zoomed into a country with the drill-down panel open, clicking a subdivision within that country would fire `toggle_country` (re-opening the panel) instead of `toggle_region` (toggling the subdivision). **Fix**: Added `drillDownCountry` state tracking — when a drill-down is open, clicks on subdivisions within that country go directly to `toggle_region`.

## Bugs Still Present

7. **`toggle_region` uses `host_places` (expanded) while other handlers use `host_places_raw`** — In `gall_host_live.ex`, the `toggle_region` handler (line 238) passes `socket.assigns.host_places` to `assign_range_data`. But `host_places` is the *expanded* leaf codes (set by `assign_range_data` itself at line 497), while `toggle_country` (line 270) and the `ExclusionDrillDown` callback (line 368) pass `host_places_raw` (the original codes from the DB query). This works by accident since leaf codes pass through `assign_range_data`'s `split_with` as leaf codes, but it's fragile. All three call sites should use `host_places_raw` for consistency.

8. **Country-level hover tooltip doesn't check exclusion status** — In the JS hook's country hover handler (lines 413-420), the tooltip shows "Documented" or "Country-level record only" based on `inRange`/`inheritedRange`, but doesn't check `excludedRange`. On the public page this doesn't matter (exclusions aren't sent), but in admin mode an excluded leaf country would show "Documented" in the tooltip while appearing red on the map.

## Inconsistencies and Design Smells

9. **Two update mechanisms for the same hook** — The host form uses the `range_map` component with data attributes and relies on `updated()` to detect changes. The gall-host page uses a raw `<div phx-hook="RangeMap">` and pushes events via `push_event("range-update", ...)`. Both work, but the gall-host page could use the component if it also pushed events (the hook handles both). Having two patterns makes the hook harder to reason about.

10. **Gall-host page uses raw hook div instead of the `range_map` component** — The component supports all needed attrs (`excluded_range`, `editable`, etc.). The raw div was likely a workaround from early development. Should be migrated to the component for consistency.

11. **Duplicated precision expansion logic** — `assign_range_data` in `gall_host_live.ex` (lines 461-502) reimplements the country-level expansion that `Ranges.split_by_precision/1` already does. The gall-host page queries `get_places_for_gall` (which returns flat codes, no precision info) and then re-expands on the client side. Meanwhile the public page uses `get_display_range_for_gall` which does the expansion properly in the context. This means the admin and public pages can show different range computations for the same gall.

12. **ExclusionDrillDown and CountryDrillDown share structure but are separate components** — Both are slide-in panels with country title, close button, subdivision list with checkboxes, and color coding. Their semantics differ (host range editing vs exclusion editing) but the UI chrome is identical. If they continue to converge, extracting a shared `DrillDown` shell component would reduce duplication.

13. **Removed bulk operations leave no replacement** — The uncommitted changes remove Select All / Deselect All buttons from both admin pages and the Exclude All / Include All buttons from ExclusionDrillDown. These were removed because they were buggy or confusing, but there's no replacement for bulk operations. For a country with 50+ subdivisions, this means 50+ individual clicks.

## Test Coverage Gaps

### Critical (core functionality untested)

14. **`get_display_range_for_gall/1` — NO TESTS** — This is the primary function combining host ranges, precision expansion, and exclusion subtraction. Used by all gall range maps. The recent bug (#3 above) lived here.

15. **`split_by_precision/1` — NO TESTS** — Private helper that expands country-level ranges to leaf descendant codes. Critical for map accuracy. The recent bug (#2 above) lived here.

16. **`get_display_range_for_host/1` — NO TESTS** — Similar to the gall version but without exclusions.

17. **`toggle_exclusion_for_gall/2` — NO TESTS** — Context function for toggling exclusions. Admin UI depends on it.

18. **ExclusionDrillDown — NO DEDICATED TESTS** — Only tested indirectly via gall_host_live smoke tests. Component lifecycle, open/close, toggle events, parent notification, and visual states are all untested.

19. **CountryDrillDown — 1 TEST** — Only tests "renders closed state by default". All user interactions (country-level toggle, subdivision toggle, select all, deselect all) are untested.

### Important (common operations)

20. **Gall range queries untested** — `get_places_for_gall/1`, `get_places_for_galls/1`, `get_host_place_ids_for_gall/1`. These compute gall range from host union.

21. **Host toggle operations untested** — `toggle_place_for_host/2`, `remove_place_from_host/2`.

22. **No exclusion fixtures in test seeds** — `gall_range_exclusion` table is empty in `test_seeds.sql`. No tests can exercise exclusion scenarios without setup boilerplate.

23. **No JS tests** — The range_map hook has ~670 lines of logic (choropleth coloring, click dispatch, bounds calculation, zoom behavior) with zero test coverage.

### Admin page test weakness

24. **Range toggle tests are smoke-only** — Both `gall_host_live_test.exs` and `host_live/form_test.exs` test `toggle_region` only to verify the page doesn't crash. No assertions on actual range state changes, persistence, or map data attributes.

25. **Drill-down workflow tests missing** — No tests for: clicking a country → panel opens → toggle subdivisions → close panel → verify state. This is the primary admin workflow for range editing.

## UI/UX Observations

26. **Map is Western Hemisphere only** — `maxBounds: [[-180, -62], [10, 86]]` hard-clips to the Western Hemisphere. Fine for now but will need adjustment for any Eastern Hemisphere expansion.

27. **`fitToRange` depends on loaded tiles** — Uses `querySourceFeatures` which only returns features from currently loaded vector tiles. If the map is zoomed into North America and range data includes South America, the bounds calculation won't include unloaded South American tiles. Falls back to hemisphere view, which works but could be jarring on range updates.

28. **No empty state for range map** — When a species has no range data at all, the map shows the full hemisphere in white. No text indicating "No range data available." The loading spinner disappears once MapLibre initializes, even if there's nothing to show.

29. **Map height inconsistency** — Default component height is `h-[400px]`. Host form overrides to `min-h-[500px]` (uncommitted change). Gall-host page uses `min-h-[350px]`. Place page uses `h-[60vh] min-h-[400px]`. No standard sizing.

30. **Legend is duplicated across pages** — Each page (gall, host, gall-host admin, host admin) has its own inline legend markup. If colors change, all four need updating. Should be a component or part of the `range_map` component.

## Code Quality

### Ranges context (`ranges.ex`)

31. **`split_by_precision` issues a DB query per country-level range** — Each country-level entry triggers `Places.leaf_descendant_ids` + a second `from(p in "place", where: p.id in ^leaf_ids, select: p.code)` query. For a host with 10 country-level ranges, that's 20 queries inside `Enum.reduce`. Should batch: collect all leaf IDs first, then do one query.

32. **`split_by_precision` queries `"place"` as a raw table string** — The `Place` schema exists and is imported via `Gallformers.Places.Place`. Using `from(p in "place", ...)` bypasses Ecto type casting and preloads. Should be `from(p in Place, ...)`.

33. **Several queries join `"place"` as a raw string instead of the Place schema** — `get_places_for_host`, `get_places_for_host_with_precision`, `get_places_for_host_species_ids`, `get_places_for_hosts`, `get_places_for_gall`, `get_places_for_galls`, `get_excluded_places_for_gall`, `get_excluded_places_with_precision_for_gall`, `get_place_id_by_code`, `get_hosts_for_place` (also uses `"alias_species"` and `"alias"` raw tables). These should all use the `Place` schema. Raw table strings are only warranted when there's no schema.

34. **`normalize_place_entries` and `normalize_exclusion_entries` are identical functions** — Both take `(species_id, entries)` and produce the same map shape. Should be a single `normalize_entries/2`.

35. **`add_place_to_host` ignores the `Repo.insert` result** — Lines 164-166: calls `Repo.insert(on_conflict: :nothing)` then unconditionally returns `{:ok, %{id: host_species_id}}`. The insert could fail for reasons other than conflict (e.g., FK violation). Same issue in `remove_place_from_host` (ignores `Repo.delete_all` result). The return value `{:ok, %{id: host_species_id}}` is also an odd shape — returning the input ID wrapped in a map isn't useful to callers.

36. **`toggle_place_for_host` and `toggle_exclusion_for_gall` do check-then-act without transactions** — Both query for existence, then insert or delete in a separate statement. Under concurrent access this is a TOCTOU race. Should use `Repo.insert(on_conflict: ...)` with `returning: true` or upsert patterns, or wrap in a transaction.

37. **`get_display_range_for_gall` uses list subtraction (`--`) on potentially large lists** — The `--` operator is O(n*m) in Elixir. For species with many ranges, `Enum.uniq(exact_codes)` after subtracting is also redundant if the input was already deduplicated by `distinct: true` in the query. Should use `MapSet` operations for clarity and performance.

38. **`set_range_exclusions_for_gall` nests a transaction inside a transaction** — It calls `Repo.transaction` which calls `Repo.delete_all` and `Repo.insert_all`. But the gall-host save handler already wraps the whole save in `Repo.transaction` (gall_host_live.ex:305). In SQLite, nested transactions use savepoints, which works but is unnecessary complexity. The context function should either accept an `Ecto.Multi` or assume it's called within a transaction.

39. **No `@impl true` on `handle_info` for ExclusionDrillDown callbacks** — `gall_host_live.ex` lines 351 and 380: the `handle_info` for ExclusionDrillDown messages lack `@impl true`. The compiler won't catch it if the callback signature drifts.

### GallHostLive (`gall_host_live.ex`)

40. **Three places with identical exclusion toggle logic** — `toggle_region` (lines 224-231), `toggle_country` leaf branch (lines 256-263), and `handle_info` for ExclusionDrillDown (lines 354-361) all do the same thing: read `excluded_place_ids`, check if `place_id` is in it, add or remove, convert to codes, and call `assign_range_data`. This should be a single `toggle_exclusion/2` helper.

41. **`assign_range_data` calls `Places.leaf_descendant_ids` per country code** — Same N+1 query problem as `split_by_precision`. Each country-level code triggers a recursive CTE query. For a gall with hosts in 5 countries, that's 5 recursive queries.

42. **`assign_range_data` rebuilds `place_by_code` and `place_by_id` maps on every call** — These are derived from `all_places` which is loaded once in `mount` and never changes. Should be computed once and stored as assigns.

43. **`recompute_host_places_and_range` bounces between IDs and codes unnecessarily** — Converts `excluded_place_ids` → codes, filters by `host_places` (codes), then converts back to IDs. This double-conversion through `all_places` is convoluted. Should work in one ID space throughout.

44. **`Repo` is aliased but only used in the save handler** — The save transaction (line 305) calls `Repo.transaction` directly in the LiveView. Per the architectural principles in CLAUDE.md, contexts own transactions, not callers. The save logic should be a `Ranges` context function.

45. **Raw hook div instead of `range_map` component in the template** — Lines 662-675 duplicate the component's HTML, JSON encoding, and data attributes. The component already supports all needed attrs. Using the component would mean one place to update if the hook contract changes.

46. **`place_ids_to_codes` and `place_codes_to_ids` do linear scans** — Both `Enum.filter` over the full `all_places` list for each conversion. With ~800 places this is fine, but the functions build `MapSet`s internally then discard them. If these are called multiple times in a request, the maps are rebuilt each time. The lookup maps built in `assign_range_data` should be reused.

### HostLive.Form (`host_live/form.ex`)

47. **`compute_map_range` duplicates the expansion logic from `Ranges.split_by_precision`** — The host form expands country codes to leaf descendants locally (lines 429-443) while the Ranges context does the same thing (lines 360-376). Two independent implementations of "expand country to leaf codes" that could drift. One source of truth in the context would be better.

48. **`compute_map_range` rebuilds `place_by_code` and `id_to_code` maps on every call** — Same issue as #42. These are derived from the static `all_places` assign.

49. **`save_place_changes` lives in the `Plants` context but assembles data from LiveView assigns** — The function takes a map with `original_exact_places`, `original_country_places`, `exact_places`, `country_places`, and `all_places`. This is socket state leaked into the context layer. The context should accept `{host_id, [{place_id, precision}]}` — the format `Ranges.update_host_places` already accepts. The LiveView should do the code→ID conversion.

50. **`toggle_place_code` appends with `++`** — Line 418: `places ++ [code]` appends to the end of a list, which is O(n). For the small lists involved this doesn't matter performance-wise, but it's non-idiomatic. Prepending with `[code | places]` is the Elixir convention unless order matters (it doesn't here — the places are unordered).

### Drill-down components

51. **`excluded?/3` in ExclusionDrillDown does a linear scan of `all_places` per call** — Called 3 times per subdivision in the render (lines 104, 105, 109). For a country with 50 subdivisions, that's 150 linear scans of the ~800-element `all_places` list. Should precompute a `MapSet` of excluded codes in `update/2`.

52. **ExclusionDrillDown and CountryDrillDown have inconsistent `notify_parent` signatures** — ExclusionDrillDown: `notify_parent(message)` (no socket arg). CountryDrillDown: `notify_parent(socket, message)` (takes socket, ignores it). Neither needs the socket. Should be consistent.

53. **CountryDrillDown doesn't filter subdivisions by any relevance** — It shows ALL subdivisions for a country. ExclusionDrillDown (after the fix) filters to only show subdivisions in the host range. CountryDrillDown should probably also filter — if editing a host's range for Canada, there's no need to show Canadian territories the user can't meaningfully interact with yet.

54. **ExclusionDrillDown's `update/2` catch-all uses `Map.take` instead of explicit assigns** — Line 44: `assign(socket, Map.take(assigns, [:excluded_place_ids, :host_places, :all_places, :id]))`. This silently ignores new assigns if the parent adds them. Explicit pattern matching is safer and documents the component's API.

### JS hook (`range_map.js`)

55. **`buildFillExpression` rebuilds `effectiveInRange` and `effectiveInherited` sets on every call** — These are the same sets used by `updateChoropleth`. The function creates new Sets from the difference of `inRange`, `excludedRange`, and `inheritedRange` each time. Since `updateChoropleth` calls `buildFillExpression` twice (once for countries, once for subdivisions), the set math runs twice per update. Should compute effective sets once and pass them in.

56. **`fitToRange` iterates ALL source features to compute bounds** — `querySourceFeatures` returns every feature loaded in the viewport. For the full hemisphere view, this can be thousands of features. Each feature's geometry coordinates are iterated. Should use a simpler approach: store bounds as metadata in the tile source, or compute bounds server-side and pass them as data attributes.

57. **`zoomToCountry` scans all features twice** — Once for country features, once for subdivision features. Both iterate the full set. Could combine into a single pass or use a filter expression.

58. **No error handling for missing PMTiles file** — If `/data/boundaries.pmtiles` is missing or fails to load, the map silently shows blue ocean. Should display an error state or fallback.

59. **Fullscreen hint uses inline CSS string** — Lines 330-334: `hint.style.cssText = 'position:fixed;top:16px;...'`. All other styling uses Tailwind classes. This should use Tailwind utilities or at minimum be a CSS class.

### Cross-cutting

60. **No type/struct for range display data** — `get_display_range_for_gall` and `get_display_range_for_host` return ad-hoc maps (`%{in_range: ..., inherited_range: ..., excluded_range: ...}`). Per CLAUDE.md principle #6 ("domain concepts deserve types"), this is a domain concept that should be a struct. Callers currently destructure the map with no compile-time safety.

61. **`MapSet` vs list inconsistency across pages** — `GallLive` converts `in_range` to a `MapSet` then back to a list for the component. `HostLive` does the same. `GallHostLive` keeps everything as lists. The `range_map` component accepts lists. If nothing needs set operations at the LiveView layer, keep them as lists throughout.

62. **Place lookup patterns vary across files** — `gall_host_live.ex` uses `Enum.find(socket.assigns.all_places, &(&1.code == code))`. `exclusion_drill_down.ex` does the same in `excluded?/3`. `host_live/form.ex` uses `Places.get_place_by_code(code)` (a DB query). Should consistently use the preloaded lookup map (build `code → place` map once from `all_places` assign).
