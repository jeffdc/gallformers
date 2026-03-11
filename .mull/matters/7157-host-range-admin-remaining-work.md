---
status: done
created: 2026-03-10
updated: 2026-03-11
epic: admin
relates: [be9d, 0df8, 383e, 154b]
---

# Host range admin — remaining work

## Current state (2026-03-10, session 2)

Branch `be9d-host-range-admin`. Compiles clean, 1516 tests pass (21 new). NOT yet committed.

### Completed

**Group A: Native/Introduced Pipeline (items 2, 3, 6)** — DONE
- Item 6: `compute_map_range` now includes `distribution_type` in host_ranges, delegates to `Ranges.compute_display_range(host_ranges, with_introduced: true)`. Removed manual introduced_range recalculation.
- Item 2: CountryDrillDown tracks `country_dist_type`, sends it with `set_country_level` messages. Native/introduced pill selector appears when country-level is on. Form handler accepts `"native"` or `"introduced"` via guard.
- Item 3: Replaced binary checkbox with tri-state indicator: gray border (none), green+check (native), amber+check (introduced). Row backgrounds match.
- Cleanup: Removed dead `toggle_exact` handler from form.ex.

**Group B: CountryDrillDown Robustness (items 7, 13)** — DONE
- Item 7: `update(%{action: {:open, country}})` now computes `exact_places` and `introduced_places` on open. Mount uses `MapSet.new()` for type consistency.
- Item 13: 22 tests (up from 1). Wrapper LiveView with `live_isolated`. Covers: closed/open, tri-state indicators, cycling, country-level toggle with dist type, bulk select/deselect, close. Key pattern: `click_and_sync` helper does `render_click` + `render(view)` to process async `notify_parent` messages.

**Group C: Host Form UX (items 1, 4)** — DONE
- Item 1: Removed `fitToRange(true)` from `updated()` in `range_map.js`. Map only fits on initial load and explicit server events.
- Item 4: "Save & Confirm Range" button added. Uses named submit button (`name="confirm_range" value="true"`) through the existing `save` form submit — NOT a separate event. Handler checks `full_params["confirm_range"] == "true"`. Merges `range_confirmed: true` into `pending_host_traits`. Flash: "Host saved and range confirmed".

### Files changed
- `lib/gallformers_web/live/admin/host_live/form.ex` — compute_map_range fix, country-level handler, save_and_confirm, dead code removal
- `lib/gallformers_web/live/admin/country_drill_down.ex` — tri-state UI, country dist type, race fix
- `assets/js/hooks/range_map.js` — removed zoom reset from updated()
- `test/gallformers_web/live/admin/country_drill_down_test.exs` — 22 tests (rewritten)

### Remaining groups

**Group D: POWO Synonym Resolution (item 5)** — NOT STARTED
- `match_by_name/1` rejects synonyms. `get_accepted_name/1` exists but is dead code. Wire up synonym fallback.
- Key files: `lib/gallformers/wcvp/lookup.ex`

**Group E: HostRangeLive Bulk Review Page (items 8, 9, 10, 11, 12, 14)** — NOT STARTED
- Filters don't work (8), no URL param persistence (9), poor sync feedback (10), no confirmation dialog (11), sync status filter not wired (12), shallow tests (14)
- Key files: `lib/gallformers_web/live/admin/host_range_live.ex`

**Group F: Integration Tests (item 15)** — NOT STARTED
- Cross-cutting scenarios. Do last.

## Execution Plan

### Group A: Native/Introduced Pipeline (items 2, 3, 6) — DONE
### Group B: CountryDrillDown Robustness (items 7, 13) — DONE
### Group C: Host Form UX (items 1, 4) — DONE
### Group D: POWO Synonym Resolution (item 5)
### Group E: HostRangeLive Bulk Review Page (items 8, 9, 10, 11, 12, 14)
### Group F: Integration Tests (item 15)

**Order: A → B → C → D → E → F**
