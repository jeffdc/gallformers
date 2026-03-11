---
status: done
created: 2026-03-10
updated: 2026-03-10
epic: geo-expansion
relates: [b9e5, be9d, 600a, 6b43, 7157]
blocks: [0df8]
---

# Host range architecture — loose ends and native/introduced gap

## Design

### Decision record

- `distribution_type` is two-value: `native` | `introduced`. No "unknown" state.
- POWO is authoritative for plant ranges. Legacy data defaults to "native" — if POWO says introduced, the sync reclassifies. That's correct, not a false conflict.
- Bulk sync does full replacement from POWO. Curator overrides happen per-host via the import screen, not bulk.
- Map click is a tri-state cycle for host range: Out → Native → Introduced → Out. Uses existing hatched pattern for introduced.
- Gall range map click stays binary (in/out). Introduced hatching is informational from host data.
- The POWO diff UI is a reusable LiveComponent, shared between host form and bulk page.
- **Drill-down panel**: Modify CountryDrillDown in-place for layers 1-2. Extract shared PlaceDrillDown component in layer 3 when gall-side migration needs it.

### State matrix: existing range vs POWO

For any place, existing state is one of {not present, native, introduced} and POWO state is one of {not present, native, introduced}. The 3×3 grid:

| Existing ↓ \ POWO → | Not present | Native | Introduced |
|---|---|---|---|
| Not present | no-op | add native | add introduced |
| Native | remove (POWO doesn't list) | agreement | reclassify native→introduced |
| Introduced | remove (POWO doesn't list) | reclassify introduced→native | agreement |

The diff UI shows six buckets derived from this matrix:
1. `add_native` — not in our range, POWO says native
2. `add_introduced` — not in our range, POWO says introduced
3. `remove` — in our range, POWO doesn't list (default: selected = keep)
4. `reclassify_to_introduced` — we have native, POWO says introduced
5. `reclassify_to_native` — we have introduced, POWO says native
6. `agree` — same in both (not shown, or shown as collapsed count)

All buckets default to "accept POWO" (all selected). Admin can uncheck individual items to reject specific changes.

### Architecture layers

**Layer 1 — Shared range editing primitives**

1. **POWO diff computation** moves to `Plants` context (currently inline in form.ex as `build_wcvp_diff`). Pure function: takes current range entries + WCVP data → returns the six-bucket diff struct. No socket/UI dependency.

2. **POWO diff review LiveComponent** — owns its own lifecycle (expand/collapse countries, toggle individual items, select/deselect all per bucket). Used by host form and bulk page.

**Layer 2 — Host range (branch be9d)**

3. **Refactor host form range state.** Replace three parallel assigns (`exact_places`, `country_places`, `introduced_place_codes`) with unified `range_entries` map: `%{code => %{precision, distribution_type}}`. Single source of truth. All event handlers, save path, and CountryDrillDown callbacks updated.

4. **Expand diff computation** to produce all six buckets. Current `build_wcvp_diff` only compares presence; needs to thread `distribution_type` from `range_entries` and compare against POWO classification.

5. **Wire tri-state map clicks** in host form. Click cycles out → native → introduced → out. Map colors: green (native), amber/hatched (introduced). Existing hatched pattern reused.

6. **Modify CountryDrillDown in-place** to accept `range_entries` and support tri-state subdivision cycling (out → native → introduced → out).

**Layer 3 — Gall range + extraction (future, separate branch)**

7. **Extract shared PlaceDrillDown component** from CountryDrillDown. Two modes: host (tri-state) and gall (binary). Tests from layer 2 assert correct behavior, making extraction low-risk.

8. **Refactor gall-host page** to use shared PlaceDrillDown in gall mode.

### What stays as-is from current branch

- `HostRange` schema with `distribution_type` field and migration — correct, no changes needed
- `host_traits` tracking (`range_confirmed`, `wcvp_synced_at`) — done
- `Ranges.update_host_places/2` — handles 3-tuples, delete-all-then-insert, correct for POWO-authoritative model
- `Plants.sync_host_from_wcvp/2` and `build_sync_place_entries/3` — correctly tags native/introduced from WCVP
- `Wcvp.Lookup.get/1` — returns separate native/introduced distribution lists
- `HostRangeLive` — bulk page structure, filters, pagination, async sync with progress bar
- `GallHostLive` — gall-host page, range curation, save flow (layer 3 refactors but doesn't rewrite)

### What gets reworked from current branch

- `build_wcvp_diff` in form.ex → moves to Plants context, gains reclassification buckets
- `apply_wcvp_updates` in form.ex → updated to work with `range_entries` map instead of three assigns
- `introduced_place_codes` assign → eliminated, absorbed into `range_entries`
- `CountryDrillDown` → modified in-place to accept `range_entries` and tri-state cycle
- `build_place_entries` / `build_place_change_entries` in form.ex / plants.ex → simplified since `range_entries` already carries distribution_type

### Sequencing

Layers 1+2 execute together on branch be9d. Layer 3 is a separate branch after be9d merges.

### Known limitation: range review family column

The `base_range_review_query` in `Plants` joins genus→family via direct `parent_id`, which skips intermediate taxonomy ranks (subfamily, tribe). Hosts with intermediate ranks will show "---" for Family in the host range review table. The recursive CTE approach from `get_hosts_tree` would fix this but adds query complexity. Tracking here for awareness — affects UX only, not data correctness.
