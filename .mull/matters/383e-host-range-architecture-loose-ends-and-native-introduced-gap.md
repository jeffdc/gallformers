---
status: refined
created: 2026-03-10
updated: 2026-03-10
epic: geo-expansion
relates: [b9e5, be9d]
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
- The drill-down panel is a shared component with two modes (host: tri-state, gall: binary toggle).

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

1. **Unified drill-down component** replacing both `CountryDrillDown` (host form) and `RangeDrillDown` (gall-host page). Configurable mode:
   - Host mode: tri-state cycle per subdivision (out → native → introduced → out)
   - Gall mode: binary toggle (in/out), introduced shown as read-only indicator
   - Supports country-level toggle (host mode only)
   - Supports bulk select/deselect
   - Sends generic messages; parent interprets

2. **POWO diff computation** moves to `Plants` context (currently inline in form.ex as `build_wcvp_diff`). Pure function: takes current range entries + WCVP data → returns the six-bucket diff struct. No socket/UI dependency.

3. **POWO diff review LiveComponent** — owns its own lifecycle (expand/collapse countries, toggle individual items, select/deselect all per bucket). Used by host form and bulk page.

**Layer 2 — Host range (this branch: be9d)**

4. **Refactor host form range state.** Replace three parallel assigns (`exact_places`, `country_places`, `introduced_place_codes`) with unified `range_entries` map: `%{code => %{precision, distribution_type}}`. Single source of truth. All event handlers, save path, and CountryDrillDown callbacks updated.

5. **Expand diff computation** to produce all six buckets. Current `build_wcvp_diff` only compares presence; needs to thread `distribution_type` from `range_entries` and compare against POWO classification.

6. **Wire tri-state map clicks** in host form. Click cycles out → native → introduced → out. Map colors: green (native), amber/different hue (introduced), hatched (out of range). Existing hatched pattern reused.

7. **Bulk host range page loose ends:**
   - Confirmation dialog before bulk sync (count summary)
   - Optional per-host diff review (same diff component from layer 1)
   - Test coverage for query functions and sync flow

**Layer 3 — Gall range (future work, separate branch)**

8. **Refactor gall-host page** to use shared drill-down component in gall mode. Current `RangeDrillDown` replaced. Behavior unchanged — binary in/out, introduced as visual indicator.

9. **Gall range bulk triage page** — same skeleton as `HostRangeLive`. Default filter: unconfirmed galls. Bulk confirm action. Click-through to gall-host page for curation. Design details deferred to when layer 2 is complete.

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
- `CountryDrillDown` → replaced by shared drill-down component
- `build_place_entries` / `build_place_change_entries` in form.ex / plants.ex → simplified since `range_entries` already carries distribution_type

### Sequencing

Layer 1 (primitives) and Layer 2 (host range) execute together on branch be9d. Layer 3 (gall range) is a separate branch after be9d merges.

Within layers 1+2, suggested order:
1. Refactor form state to `range_entries` map (step 4) — foundational, everything else depends on it
2. Move diff computation to Plants context and add reclassification buckets (steps 2, 5)
3. Build shared drill-down component, wire into host form (step 1, replacing CountryDrillDown)
4. Build diff review LiveComponent (step 3)
5. Wire tri-state map clicks (step 6)
6. Bulk page loose ends (step 7)
7. Test coverage across all workflows

### Matters housekeeping

- f6d4: already marked done — phase 1 (gall_range table, curation UI) shipped. Layers 2-3 of f6d4's plan (bulk admin, further refinement) are captured here as layer 3.
- b9e5: bulk WCVP backfill — depends on this work completing. Keep as-is.
- be9d: this is the execution branch. Relates to 383e.
