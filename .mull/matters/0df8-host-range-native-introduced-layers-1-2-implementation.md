---
status: done
created: 2026-03-10
updated: 2026-03-10
epic: geo-expansion
relates: [be9d, b9e5, 7157]
blocks: [600a, 6b43]
needs: [383e]
docket: true
---

# Host range native/introduced — layers 1-2 implementation

## Implementation Plan

**Goal:** Deliver native/introduced support across host range editing — shared primitives (Layer 1) and host-specific features (Layer 2) — so that POWO data flows correctly through all admin workflows.

**Architecture:** Unified `range_entries` map replaces three parallel assigns in the host form. POWO diff computation moves to the Plants context as a pure function. Drill-down panel becomes a shared component with host-mode (tri-state) and gall-mode (binary). POWO diff review becomes its own LiveComponent, reusable in both host form and bulk page.

**Branch:** `be9d-host-range-admin` (continuing existing work)

---

### Task 1: Refactor host form range state to unified `range_entries` map

This is foundational — every subsequent task depends on it.

**Files:**
- Modify: `lib/gallformers_web/live/admin/host_live/form.ex` (assigns, event handlers, save path)
- Modify: `lib/gallformers/plants.ex` (`save_place_changes/2`, `build_place_change_entries/4`)
- Test: `test/gallformers_web/live/admin/host_live/form_test.exs`

**Behavior:**

Replace these assigns:
```
exact_places: [code]
country_places: [code]
introduced_place_codes: MapSet
original_exact_places: [code]
original_country_places: [code]
```

With:
```
range_entries: %{code => %{precision: "exact"|"country", distribution_type: "native"|"introduced"}}
original_range_entries: %{code => %{precision, distribution_type}}
```

`load_host_for_edit/2` (line ~87): Build `range_entries` from `Ranges.get_places_for_host_with_precision/1` which already returns `%{code, precision, place_id, distribution_type}` maps.

`compute_map_range/1` (line ~632): Iterate `range_entries` instead of concatenating `exact_places` + `country_places`. Compute `introduced_range` from entries with `distribution_type == "introduced"` instead of cross-referencing `introduced_place_codes`.

`save_host/2` for `:edit` mode (line ~1004): Build `place_changes` from `range_entries` and `original_range_entries` instead of the six separate assigns.

`Plants.save_place_changes/2` (line ~548): Accept the new shape. Dirty check compares `range_entries != original_range_entries`. Build 3-tuples directly from map values — no more `build_place_change_entries` cross-referencing a separate `introduced_codes` set.

CountryDrillDown callback handlers (lines ~1147-1180): Update to modify `range_entries` map instead of `exact_places`/`country_places` lists. `{:toggle_exact, code}` adds/removes from `range_entries` with `%{precision: "exact", distribution_type: "native"}` as default. `{:set_country_level, code, bool}` sets/removes an entry with `precision: "country"`.

`build_default_assigns/1`: Replace the five old assigns with `range_entries: %{}` and `original_range_entries: %{}`.

**Testing:**
- Load existing host with mixed native/introduced range → `range_entries` map has correct distribution_types
- Add subdivision via CountryDrillDown → entry appears in `range_entries` as native/exact
- Toggle country-level → entry appears as native/country
- Save with no changes → no DB write (dirty check passes)
- Save with changes → correct 3-tuples written via `update_host_places`
- Round-trip: save introduced entries, reload, verify they're still introduced

**Notes:**
- The `save_wcvp_data/2` path (new host creation from WCVP) also needs updating — it uses `build_place_entries` which references the old assigns. But this path is simpler since it goes directly from WCVP data to 3-tuples; it doesn't need the `range_entries` map. Keep it as-is for now; it already works correctly.
- `compute_map_range` currently passes entries to `Ranges.compute_display_range/1` — that function's contract doesn't change, it already accepts `%{code, precision, place_id}` maps.

---

### Task 2: Move POWO diff computation to Plants context

**Files:**
- Modify: `lib/gallformers/plants.ex` (new public function)
- Modify: `lib/gallformers_web/live/admin/host_live/form.ex` (remove `build_wcvp_diff/2`, call Plants instead)
- Create: `test/gallformers/plants/powo_diff_test.exs`

**Behavior:**

Extract `build_wcvp_diff` from form.ex into `Plants.compute_powo_diff/2`:

```elixir
@spec compute_powo_diff(range_entries :: map(), wcvp_data :: map()) :: PowoDiff.t()
def compute_powo_diff(range_entries, wcvp_data)
```

Takes:
- `range_entries` — the unified map from Task 1: `%{code => %{precision, distribution_type}}`
- `wcvp_data` — the struct from `Wcvp.Lookup.get/1` with `native_distribution` and `introduced_distribution`

Returns a struct (or map) with six buckets:

```elixir
%{
  add_native: [code],           # not in range, POWO says native
  add_introduced: [code],       # not in range, POWO says introduced
  remove: [code],               # in range, POWO doesn't list
  reclassify_to_introduced: [code],  # we have native, POWO says introduced
  reclassify_to_native: [code],      # we have introduced, POWO says native
  agree_count: integer(),        # same in both (just a count for display)
  # Grouped versions for the UI tree (same structure as current adds_groups etc.)
  add_native_groups: grouped,
  add_introduced_groups: grouped,
  remove_groups: grouped,
  reclassify_to_introduced_groups: grouped,
  reclassify_to_native_groups: grouped,
  # Selection state (all default to "accept POWO")
  selected_add_native: MapSet,
  selected_add_introduced: MapSet,
  selected_remove: MapSet,       # selected = KEEP (same semantics as current)
  selected_reclassify_to_introduced: MapSet,
  selected_reclassify_to_native: MapSet,
  # Metadata
  wcvp_data: wcvp_data,
  has_changes: boolean(),
  expanded_countries: MapSet
}
```

The grouping helper `group_places_by_country` stays in form.ex or moves with the diff — it needs `place_by_code` which is a UI assign. Consider: the Plants function returns flat lists, and the caller (form or LiveComponent) groups them for display. This keeps the context function pure (no place_by_code dependency).

Actually, cleaner: `compute_powo_diff/2` returns flat lists + metadata. A separate `Plants.group_diff_for_display/2` takes the diff + `place_by_code` and returns the grouped/selected version. The diff LiveComponent (Task 4) calls this on mount.

**Testing:**
- Empty range + POWO data → all in `add_native` / `add_introduced`
- Exact match → `agree_count` equals total, all change buckets empty
- Range has places POWO doesn't → those in `remove`
- Range has native, POWO says introduced → in `reclassify_to_introduced`
- Range has introduced, POWO says native → in `reclassify_to_native`
- Mixed scenario → correct distribution across all buckets, no place appears in multiple buckets
- POWO data is nil/empty → no crash, empty diff

**Notes:**
- The TDWG code conversion (`Wcvp.Tdwg.convert_tdwg_codes`) stays where it is — this function receives already-converted place codes via `wcvp_data.native_distribution` and `wcvp_data.introduced_distribution`. Wait — actually those are TDWG distribution objects, not place codes. The conversion needs to happen before calling `compute_powo_diff`. The caller loads `tdwg_lookup` and converts. This matches the current flow where `build_wcvp_diff` does the conversion inline.
- Revised signature: `compute_powo_diff(range_entries, native_codes, introduced_codes)` where the caller has already converted TDWG→place codes. Simpler, more testable.

---

### Task 3: Shared drill-down component

**Files:**
- Create: `lib/gallformers_web/live/admin/place_drill_down.ex`
- Modify: `lib/gallformers_web/live/admin/host_live/form.ex` (swap CountryDrillDown → PlaceDrillDown)
- Modify: `lib/gallformers_web/live/admin/gall_host_live.ex` (swap RangeDrillDown → PlaceDrillDown, deferred to Layer 3 but design the component API to support it now)
- Test: `test/gallformers_web/live/admin/place_drill_down_test.exs`

**Behavior:**

New `PlaceDrillDown` LiveComponent replaces both `CountryDrillDown` and `RangeDrillDown`. Single component, two modes configured by the `mode` assign.

Props:
```elixir
<.live_component
  module={PlaceDrillDown}
  id="place-drill-down"
  mode={:host}              # :host (tri-state) or :gall (binary)
  range_entries={@range_entries}  # host mode: the unified map
  # OR for gall mode:
  in_range_codes={@in_range_codes}
  omitted_codes={@omitted_codes}
  introduced_codes={@introduced_codes}  # gall mode: read-only indicator
  all_places={@all_places}
/>
```

Messages sent to parent:

Host mode:
- `{PlaceDrillDown, {:set_entry, code, %{precision: p, distribution_type: dt}}}` — add/update
- `{PlaceDrillDown, {:remove_entry, code}}` — remove from range
- `{PlaceDrillDown, {:set_country_level, code, boolean}}` — country-level toggle
- `{PlaceDrillDown, :zoom_out}` — close panel

Gall mode (unchanged from current RangeDrillDown):
- `{PlaceDrillDown, {:toggle_place, code}}`
- `{PlaceDrillDown, {:include_all, codes}}`
- `{PlaceDrillDown, {:exclude_all, codes}}`
- `{PlaceDrillDown, :zoom_out}`

Host mode tri-state cycle on subdivision click:
- Not in range → add as native (green)
- Native → switch to introduced (amber)
- Introduced → remove from range

Subdivision display:
- Host mode: green bg for native, amber bg for introduced, no bg for not-in-range. All three states visible.
- Gall mode: green bg for in-range, red bg for excluded, amber "intro" label for introduced host range (read-only). Same as current RangeDrillDown.

Country-level toggle: host mode only. Same behavior as current CountryDrillDown.

Bulk buttons:
- Host mode: "Select all native" / "Select all introduced" / "Deselect all"
- Gall mode: "Select all" / "Deselect all" (same as current)

**Testing:**
- Host mode: click subdivision cycles through out → native → introduced → out
- Host mode: country-level toggle sends correct message
- Host mode: bulk select all sets everything to native
- Gall mode: click toggles in/out
- Gall mode: introduced indicator shows but is not interactive
- Both modes: panel opens with correct subdivision list, closes on close event

**Notes:**
- `CountryDrillDown` and `RangeDrillDown` are not deleted until the gall-host page is also migrated (Layer 3). During Layer 2, only the host form switches to `PlaceDrillDown`. `RangeDrillDown` stays for `GallHostLive`.
- The existing `drill_down_panel` function component in `form_components.ex` (line 943) is the shared shell — `PlaceDrillDown` renders it. No change needed to the shell.

---

### Task 4: POWO diff review LiveComponent

**Files:**
- Create: `lib/gallformers_web/live/admin/powo_diff_review.ex`
- Modify: `lib/gallformers_web/live/admin/host_live/form.ex` (replace inline diff UI + event handlers)
- Test: `test/gallformers_web/live/admin/powo_diff_review_test.exs`

**Behavior:**

Extracts ~200 lines of diff UI and ~100 lines of event handlers from form.ex into a self-contained LiveComponent.

Props:
```elixir
<.live_component
  module={PowoDiffReview}
  id="powo-diff"
  diff={@powo_diff}          # from Plants.compute_powo_diff
  place_by_code={@place_by_code}
/>
```

The component owns:
- Expand/collapse country groups (currently `expanded_countries` in the diff struct — moves to component assign)
- Toggle individual items per bucket (currently 5 separate event handlers in form.ex)
- Select all / Deselect all per bucket (currently 6 event handlers in form.ex)
- The "include introduced" master toggle (currently `toggle_wcvp_diff_introduced`)

Messages sent to parent:
- `{PowoDiffReview, {:apply, selections}}` — user clicked "Apply Selected Changes". `selections` is a map of the five selected_* MapSets.
- `{PowoDiffReview, :cancel}` — user clicked Cancel.

The parent (form.ex or bulk page) receives `{:apply, selections}` and translates it into range_entries changes. This is the `apply_wcvp_updates` logic from form.ex, simplified because it operates on `range_entries` map:
- For each code in `selected_add_native`: add `%{precision: "exact", distribution_type: "native"}`
- For each code in `selected_add_introduced`: add `%{precision: "exact", distribution_type: "introduced"}`
- For each code in `remove` but NOT in `selected_remove`: delete from `range_entries`
- For each code in `selected_reclassify_to_introduced`: update `distribution_type: "introduced"`
- For each code in `selected_reclassify_to_native`: update `distribution_type: "native"`

Template: Uses the existing `.selectable_tree` component (form_components.ex line 1526) for each non-empty bucket. Six sections with distinct colors:
- Add native: green (existing)
- Add introduced: amber (existing)
- Remove: red (existing)
- Reclassify to introduced: amber with different label
- Reclassify to native: green with different label

Also shows `agree_count` as a collapsed summary line: "N places match — no changes needed"

**Testing:**
- Renders all non-empty buckets with correct labels
- Toggle individual item updates selection state
- Select all / deselect all per bucket
- Apply sends correct selections to parent
- Cancel sends cancel to parent
- Empty diff shows "no differences" message
- Expand/collapse country groups within each bucket

**Notes:**
- This is a significant reduction in form.ex complexity. Currently form.ex has ~15 event handlers for the diff UI. After extraction, it has 2 (handle the apply message, handle the cancel message).
- The `.selectable_tree` component already supports all the visual customization via props (container_class, text_class, etc.). The LiveComponent just renders multiple `.selectable_tree` instances with different configs.

---

### Task 5: Tri-state map click cycle in host form

**Files:**
- Modify: `lib/gallformers_web/live/admin/host_live/form.ex` (map click handler, push_event data)
- Modify: `assets/js/hooks/range_map.js` (click handler, color logic for introduced)
- Modify: `lib/gallformers_web/components/data_display_components.ex` (range_map component — new prop or updated push format)
- Test: `test/gallformers_web/live/admin/host_live/form_test.exs`

**Behavior:**

Current host form map click (`handle_event("toggle_region", ...)`) is binary — adds to `exact_places` or removes. Change to tri-state:

1. Code not in `range_entries` → add as `%{precision: "exact", distribution_type: "native"}`
2. Code in `range_entries` with `distribution_type: "native"` → change to `"introduced"`
3. Code in `range_entries` with `distribution_type: "introduced"` → remove from `range_entries`

The `push_event("range-update", ...)` call in `compute_map_range` needs to send introduced range as a separate array (it already does via `introduced_range` assign). The JS hook already handles `introduced_range` with the hatched pattern from the gall-host work (f6d4). Verify it works on the host form — the range_map component already accepts `introduced_range` as a prop.

Map coloring for host admin:
- Green fill: native range (in `in_range`)
- Amber/orange fill: introduced range (in `introduced_range`) — or use hatched, same as gall page
- Light green: inherited (country-level expansion)
- White/plain: not in range

Decision: use hatched pattern for introduced on host form too, matching gall-host page. Consistent visual language across admin.

`compute_map_range/1` update: After Task 1, this function iterates `range_entries`. Entries with `distribution_type: "introduced"` go into `introduced_range`. Entries with `distribution_type: "native"` go into `in_range`. This replaces the current cross-reference against `introduced_place_codes`.

**Testing:**
- Click empty region → appears as native (green/solid)
- Click native region → changes to introduced (hatched)
- Click introduced region → removed from range
- Map push_event includes correct `introduced_range` array
- Verify hatched pattern renders for introduced entries

**Notes:**
- The range_map JS hook's click handler currently sends `toggle_region` for leaf places and `toggle_country` for countries with subdivisions. The tri-state cycle is only in the LiveView handler — no JS changes needed for the click itself, just the visual rendering.
- For countries with subdivisions, clicking opens the drill-down (Task 3). The drill-down handles the tri-state per-subdivision.

---

### Task 6: Wire POWO diff review into host form

**Files:**
- Modify: `lib/gallformers_web/live/admin/host_live/form.ex` (swap inline diff for LiveComponent, handle messages)
- Test: `test/gallformers_web/live/admin/host_live/form_test.exs`

**Behavior:**

Replace the inline diff UI (lines ~1514-1614 of form.ex) with:
```heex
<.live_component
  :if={@powo_diff}
  module={PowoDiffReview}
  id="powo-diff"
  diff={@powo_diff}
  place_by_code={@place_by_code}
/>
```

Replace the `wcvp_diff` assign with `powo_diff`. Update `handle_event("refresh_from_wcvp", ...)` to call `Plants.compute_powo_diff/3` instead of the removed `build_wcvp_diff/2`.

Handle the apply message:
```elixir
def handle_info({PowoDiffReview, {:apply, selections}}, socket) do
  range_entries = apply_powo_selections(socket.assigns.range_entries, selections)
  # ... update assigns, set pending_host_traits, compute_map_range, mark_dirty
end
```

`apply_powo_selections/2` is a pure function (could live in Plants context or as a private in form.ex — keep in form.ex for now since it directly produces the `range_entries` map shape):
- Adds from `selected_add_native` and `selected_add_introduced`
- Removes codes in `remove` bucket that were deselected (unchecked = remove)
- Applies reclassifications

Delete from form.ex:
- `build_wcvp_diff/2` (~50 lines)
- `wcvp_section_fields/2`
- `update_wcvp_expanded/3`
- All `toggle_wcvp_diff_*` event handlers (~15 handlers, ~80 lines)
- All `select_all_wcvp_diff_*` / `deselect_all_wcvp_diff_*` event handlers
- The `toggle_group_wcvp_*` and `expand_wcvp_*` handlers
- The diff template section (~80 lines of HEEx)

Net reduction: ~250-300 lines from form.ex.

**Testing:**
- Refresh from POWO → diff component appears with correct buckets
- Apply all defaults → range_entries updated with all POWO data
- Deselect some adds → those places not added
- Deselect some removes (= keep) → those places stay in range
- Apply reclassifications → distribution_type updated in range_entries
- Cancel → diff dismissed, range_entries unchanged
- Save after applying diff → correct data persisted

**Notes:**
- The WCVP no-match search flow (`wcvp_nomatch_search` assign and handlers) stays in form.ex — it's about resolving the WCVP identity, not reviewing the diff. Once a match is found, it feeds into `compute_powo_diff` and the diff component.
- `pending_host_traits` (wcvp_id, powo_id, wcvp_synced_at) is set when the diff is applied, same as current behavior.

---

### Task 7: Bulk page confirmation dialog and optional diff review

**Files:**
- Modify: `lib/gallformers_web/live/admin/host_range_live.ex` (confirmation modal, optional diff)
- Test: `test/gallformers_web/live/admin/host_range_live_test.exs`

**Behavior:**

**Confirmation dialog:** When admin clicks "Sync Selected from WCVP", instead of firing immediately, show a modal:
```
Sync N hosts from WCVP?
  - M have WCVP links (will sync directly)
  - K need name matching
  - J have existing ranges that will be updated

[Cancel] [Sync All]
```

Use the existing `.modal` component from core_components.ex. The counts come from inspecting `hosts_to_sync` against their `wcvp_id` and `range_count` fields (already loaded in the list).

**Optional per-host diff review:** This is a stretch goal for this branch. The diff LiveComponent (Task 4) could be rendered inline per-host row, but the bulk page loads hosts as summary rows — it doesn't have their full `range_entries`. Loading range_entries per-host on demand adds complexity. Defer to a follow-up: capture as a note in the matter, don't implement now. The confirmation dialog is sufficient for safe bulk operations.

**Testing:**
- Click "Sync Selected" → modal appears with correct counts
- Cancel → modal dismissed, no sync
- Confirm → sync starts (existing progress bar behavior)
- Modal shows different counts for different selections

**Notes:**
- Also wire up the sync_status filter dropdown that exists in backend but not UI. The `apply_sync_status_filter/3` function exists in plants.ex. Add a fourth filter dropdown to the filter bar: "Sync: All / Never / Stale / Current".
- Test coverage for existing query functions (`list_hosts_for_range_review`, `count_hosts_for_range_review`) — add explicit tests if not already covered.

---

### Task 8: Test coverage and cleanup

**Files:**
- Modify: `test/gallformers_web/live/admin/host_live/form_test.exs`
- Modify: `test/gallformers_web/live/admin/host_range_live_test.exs`
- Modify: `test/gallformers/plants_test.exs`
- Delete: `lib/gallformers_web/live/admin/country_drill_down.ex` (replaced by PlaceDrillDown)
- Cleanup: remove any dead code from form.ex left over from extraction

**Behavior:**

Integration test scenarios that cut across tasks:

1. **Full POWO import round-trip:** Load host with legacy range (all native) → refresh from POWO → POWO says some are introduced → diff shows reclassification bucket → apply → save → reload → verify distribution_types correct in DB
2. **Manual edit with distribution_type:** Load host → click map to add place as native → click again to change to introduced → click again to remove → save → verify
3. **POWO import then manual override:** Import from POWO (sets some as introduced) → manually change one back to native via drill-down → save → verify override persisted
4. **Bulk sync preserves distribution_type:** Bulk sync N hosts → verify each has correct native/introduced entries from WCVP data

Cleanup:
- Delete `CountryDrillDown` after verifying nothing else references it
- Remove `introduced_place_codes`, `exact_places`, `country_places` assigns if any stragglers remain
- Remove `build_place_entries/2` and `tag_place_entries/2` from form.ex if no longer called

**Notes:**
- Run `mix precommit` at the end to verify everything compiles clean with `--warnings-as-errors`, all tests pass, credo clean, formatted.
- The old WCVP modules being deleted on this branch (matcher, reader, reporter, reports, reconciliation_live, mix tasks) are unrelated cleanup that was already staged. Commit them separately.

---

### Sequencing

```
Task 1 (range_entries refactor)
  └── Task 2 (diff to Plants context)
  │     └── Task 4 (diff LiveComponent)
  │           └── Task 6 (wire into form)
  └── Task 3 (shared drill-down)
  └── Task 5 (tri-state map click)
  └── Task 7 (bulk page confirmation)
  └── Task 8 (integration tests + cleanup)
```

Tasks 2, 3, and 5 can proceed in parallel after Task 1. Task 4 depends on Task 2. Task 6 depends on Tasks 1, 2, and 4. Task 7 is independent of 2-6. Task 8 is last.
