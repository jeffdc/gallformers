---
status: done
created: 2026-03-03
updated: 2026-03-10
epic: geo-expansion
relates: [8900, b9e5, be9d, 600a]
blocks: [be9d]
---

# Gall range curation system

GitHub: jeffdc/gallformers#522 (Megachile)

## Problem

Now that we're global, many galls occur only in their native range but their host plants are widely cultivated elsewhere. The current system computes a gall's range on the fly as the union of all host ranges minus admin exclusions. This means:

1. When a host gains introduced range (e.g., Q. robur gets NE US from WCVP), every gall on that host automatically expands — wrong for most galls
2. Admins must manually exclude introduced places one by one — tedious when a host is planted across dozens of countries
3. Even within native range, a host's range is often larger than the gall's (e.g., trees spanning into Florida but galls not present there)

## Root cause

Two problems:
1. `host_range` has no `distribution_type` column — native vs introduced is lost at save time
2. Gall range is computed on the fly, not stored — there's no place for curated admin decisions to live durably

## Design

### 1. `distribution_type` on `host_range`

Add column: `distribution_type TEXT NOT NULL DEFAULT 'native' CHECK (distribution_type IN ('native', 'introduced'))`. Manually-added entries default to `native`. All insert paths updated to pass distribution_type. Host form WCVP flows preserve the native/introduced distinction through to save.

### 2. Stored gall range — `gall_range` table

New table: `(species_id, place_id, precision)` — same shape as host_range without distribution_type. This is the source of truth for "where does this gall occur." Every consumer (public pages, ID filters, search, maps) reads from this table instead of computing from hosts.

The gall_range table replaces the current on-the-fly computation. It stores the final curated result — the places where the gall actually occurs, period.

### 3. Gall range computation + curation

Base computation: union of all host native ranges for the gall. This is the starting point. Introduced host range is excluded by default.

#### Map visual system

The map uses two orthogonal visual dimensions:

**Pattern layer** (informational — native vs introduced host range):
- Solid fill — native host range
- Hatched/striped pattern — introduced host range
- Plain/white — not in any host range (not selectable)

**Color layer** (same rules regardless of native/introduced):
- Green — in `gall_range` (confirmed present)
- Light green — inherited (country-level expansion)
- Red — excluded from `gall_range` (in host range but not in gall range)

Combined examples:
- Solid green — native host range, gall is present
- Solid red — native host range, admin excluded this place
- Hatched red — introduced host range, not in gall range (the default)
- Hatched green — introduced host range, admin included this place in gall range

All colored places (solid or hatched) are clickable to toggle inclusion/exclusion. White places are not selectable.

#### Admin interaction model

1. Admin selects a gall
2. Map shows the full picture immediately — native range in solid, introduced in hatched, colors show inclusion/exclusion
3. Click any colored place to toggle its inclusion in `gall_range`
4. Click a country with subdivisions → opens drill-down (same as today). Subdivisions that are introduced host range get a visual indicator.
5. Save writes the result to `gall_range`

No "show/hide introduced" toggle needed — the hatching makes it always visible without visual clutter.

#### When host range changes (recomputation)

When a gall is flagged for review (host range changed), the admin opens it and sees the current state. New native places from the host update appear as solid red (excluded by default since they weren't in `gall_range`). New introduced places appear as hatched red (also excluded by default). The admin reviews and includes/excludes as needed.

#### Button states

- **No review flag**: Save, Cancel (same as today)
- **Review flag set**: Save, Cancel, and "Save & Confirm Range"
  - Save — saves changes but does NOT clear the flag (admin may not be done reviewing)
  - Save & Confirm Range — saves changes AND clears `range_confirmed` flag
  - A banner shows at top of range section: "Host range data has changed since this gall's range was last confirmed."

Public pages just use `gall_range` directly — no exclusion/introduced distinction needed.

### 4. Confirmation + invalidation pattern

Same pattern as host range (matter be9d):
- `range_confirmed` (boolean) on gall traits — "an admin is happy with this gall's range"
- `range_computed_at` (datetime) — "when this gall's range was last computed/curated"

**Invalidation cascade:** When a host's range changes (WCVP sync adds/removes places), all galls on that host get `range_confirmed` set to false. The stored `gall_range` doesn't change automatically — it just gets flagged for review.

The cascade: WCVP update → host range changes → gall range flagged for review → admin curates → gall range confirmed.

### 5. Gall range bulk admin page

Parallel to be9d (host range bulk admin). Triage page for galls whose range needs attention:
- Default filter: `NOT range_confirmed` or `range_computed_at` is stale
- Admin reviews, curates, confirms
- Confirmed galls drop off the list until a host range change invalidates them

### 6. Migration path for existing exclusions

The current `gall_range_exclusion` table stores admin exclusions. When migrating to stored `gall_range`:
- For each gall, compute: union of host ranges minus existing exclusions → write to `gall_range`
- This preserves all existing admin curation work
- Then `gall_range_exclusion` can be dropped

## Consumer migration

All consumers switch from computing gall range on the fly to reading from `gall_range`:

| Consumer | Current | After |
|----------|---------|-------|
| Public gall page | `get_display_range_for_gall/1` (computes from hosts) | Read from `gall_range` |
| Gall API | `get_places_for_gall/1` + exclusions | Read from `gall_range` |
| ID filter | Joins `host_range` + exclusion subquery | Joins `gall_range` (simpler) |
| Gall-host admin | Computes from hosts + exclusions | Loads both `gall_range` AND host ranges for visual comparison |
| Range map JS | Three flat code arrays | Same format, adds hatched pattern for introduced |

## Implementation plan

### Phase 1: host_range foundation

#### Task 1: Schema migration — add `distribution_type` to `host_range`

**Files:**
- Create: `priv/repo/migrations/<timestamp>_add_distribution_type_to_host_range.exs`
- Modify: `lib/gallformers/ranges/host_range.ex` (add field + changeset validation)

**Behavior:**
Migration adds `distribution_type TEXT NOT NULL DEFAULT 'native'` with a CHECK constraint. HostRange schema gets `:distribution_type` field with `default: "native"` and `validate_inclusion` for `~w(native introduced)`.

**Testing:**
- Migration runs cleanly (up and down)
- Changeset accepts/rejects valid/invalid values
- Default is "native" when not specified

#### Task 2: Update insert paths to pass `distribution_type`

**Files:**
- Modify: `lib/gallformers/ranges.ex` — `add_place_to_host/3`, `normalize_entries/2`, `update_host_places/2`, `toggle_place_for_host/2`
- Test: `test/gallformers/ranges_test.exs`

**Behavior:**
`add_place_to_host` gets optional distribution_type param. `normalize_entries` accepts `{place_id, precision, distribution_type}` triples. Manual toggles default to "native".

**Testing:**
- Round-trip: insert with "introduced", query back, verify
- Default behavior unchanged for existing callers

#### Task 3: Host form — preserve native/introduced through WCVP flows

**Files:**
- Modify: `lib/gallformers_web/live/admin/host_live/form.ex`
- Modify: `lib/gallformers/ranges.ex` — caller contract

**Behavior:**
Host form already tracks native vs introduced separately in assigns. Change save path to pass `{place_id, precision, distribution_type}` tuples instead of flat place_id lists.

**Testing:**
- New host from WCVP → correct distribution_type on host_range rows
- WCVP refresh → introduced places tagged correctly
- Manual map edits default to "native"

### Phase 2: gall_range system

#### Task 4: Schema — `gall_range` table + gall_traits fields

**Tables:**
- Create `gall_range` table: `(species_id INTEGER, place_id INTEGER, precision TEXT, PRIMARY KEY (species_id, place_id))`
- Add `range_confirmed` (boolean, default false) and `range_computed_at` (datetime, nullable) to `gall_traits`

**Migration also populates `gall_range`:**
- For each gall: compute union of host ranges minus existing exclusions → insert into `gall_range`
- This preserves all existing admin curation work
- Drop `gall_range_exclusion` table after migration

#### Task 5: Range queries — repoint consumers to `gall_range`

**Files:**
- Modify: `lib/gallformers/ranges.ex` — new functions to read from `gall_range`, deprecate/remove on-the-fly computation
- Modify: `lib/gallformers/galls/identification.ex` — `apply_place_filter` joins `gall_range` instead of `host_range` + exclusion subquery
- Modify: `lib/gallformers_web/live/gall_live.ex` — read from `gall_range`
- Modify: `lib/gallformers_web/controllers/api/gall_controller.ex` — read from `gall_range`

**Testing:**
- Public gall page shows same range as before migration (data preserved)
- ID filter returns same galls for same place queries (behavior preserved)
- API returns same range data

#### Task 6: Gall-host admin page — curation UI

**Files:**
- Modify: `lib/gallformers_web/live/admin/gall_host_live.ex` — load gall_range + host_ranges, compute visual categories, new save logic
- Modify: `lib/gallformers_web/live/admin/exclusion_drill_down.ex` — add introduced indicator for subdivisions
- Modify: `lib/gallformers_web/components/data_display_components.ex` — `range_map` component: add `introduced_range` attribute for hatching
- Modify: `assets/js/hooks/range_map.js` — hatched pattern for introduced, updated `buildFillExpression`
- Modify: `lib/gallformers_web/components/data_display_components.ex` — update legend

**Behavior:**
On load: fetch `gall_range` + all host ranges (with distribution_type). Compute visual categories by set comparison. Map renders with solid/hatched × green/light-green/red system. Click toggles inclusion. Save writes to `gall_range`.

Review flag: when `range_confirmed` is false, show banner + "Save & Confirm Range" button alongside normal Save. Save & Confirm sets `range_confirmed = true` and `range_computed_at = now()`.

**Testing:**
- Native range place toggle works (green ↔ red)
- Introduced range place toggle works (hatched green ↔ hatched red)
- Save writes correct gall_range entries
- Save & Confirm clears flag
- Save without confirm leaves flag set
- Drill-down shows introduced indicator

#### Task 7: Invalidation cascade

**Files:**
- Modify: `lib/gallformers/ranges.ex` or new module — when host range changes, invalidate gall range_confirmed for affected galls

**Behavior:**
When `update_host_places/2` or `add_place_to_host` modifies a host's range, find all galls linked to that host and set `range_confirmed = false` on their gall_traits.

**Testing:**
- Update host range → galls on that host get range_confirmed = false
- Galls on other hosts unaffected
- Already-false flags stay false (idempotent)

### Phase 3: bulk admin

#### Task 8: Gall range bulk admin page

Parallel to be9d (host range bulk admin). Triage page for galls needing range review.

- Default filter: `NOT range_confirmed`
- List: gall name, host count, range count, confirmed status
- Bulk actions: "Confirm selected" (mark range as confirmed without changes)
- Click through to gall-host admin page for curation

Design details to be refined when Phase 2 is complete.

## Sequencing

1. Phase 1: Tasks 1-3 (host_range distribution_type) — can execute now
2. Phase 2: Tasks 4-7 (gall_range system) — after Phase 1
3. Phase 3: Task 8 (bulk admin) — after Phase 2
