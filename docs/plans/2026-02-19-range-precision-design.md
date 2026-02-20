# Range Precision System Design

## Problem

Host range data comes at different resolution levels. Some sources (like WCVP) provide country-level data only ("this plant exists in Mexico") while field observations confirm specific states. The admin UI treats everything as exact, losing this distinction. The public pages and ID tool don't communicate the difference to users.

## Data Model

Two precision levels: `exact` and `country`. The `continent` level is dropped.

### host_range table

No schema change needed — the `precision` column already exists.

| precision | place_id points to | meaning |
|-----------|-------------------|---------|
| `exact` | state/province or leaf country | Documented in this specific location |
| `country` | country with subdivisions | Present in this country; state-level data unavailable |

Both can coexist for the same country. A host can have a country-level Mexico row AND an exact Oaxaca row simultaneously. The country-level row represents the data we have from coarser sources; the exact row represents confirmed state-level data. They are independent entries, not competing states.

**Leaf countries** (Grenada, Bahamas, etc. — no subdivisions): Always stored as `exact`. There is nothing to be imprecise about.

### gall_range_exclusion table

Exclusions remain `exact` only. The precision column stays but is always `"exact"`.

## Admin Host Form — Country Drill-Down

### Hemisphere View (default)

The map shows the full Western Hemisphere with current range data:
- Green: states/provinces with exact range rows
- Light green: states/provinces inherited from a country-level row
- White: not in range

**Click interactions:**
- Click a **country with subdivisions** → opens the country panel, map zooms to that country
- Click a **leaf country** → toggles it directly (exact precision), no panel
- Click a **state/province** → toggles it directly (exact precision), same as today

The current Select All / Deselect All buttons are removed from the hemisphere view. They move into the country panel where they are scoped and useful.

### Country Panel

When a curator clicks a country, a panel slides in beside the map. The map zooms to fit the selected country. The panel contains:

**Header:** Country name and a close/back button.

**Country-level toggle:** A switch labeled "Country-level range." When turned on, help text appears: "All states shown as probable — check individual states to mark as documented." This toggle controls a single `host_range` row with `precision = "country"` pointing to the country's place ID.

**Subdivision checkbox list:** Alphabetically sorted. Each state/province has a checkbox.
- Checked = an exact `host_range` row exists for this state ("documented")
- Unchecked + country toggle on = no exact row, but inherited from country-level row (shown with subtle styling like a light background)
- Unchecked + country toggle off = not in range

**Bulk buttons** above the list: "Select all" / "Deselect all." These control exact-level checkboxes only. They do not affect the country-level toggle.

**Map sync:** Clicking a state on the map toggles its checkbox in the panel, and vice versa. The map colors update live:
- Green for checked states (exact)
- Light green for unchecked states when country toggle is on (inherited)
- White for unchecked states when country toggle is off

**Returning to hemisphere:** Close/back button on the panel slides the panel away and zooms the map back to the hemisphere view.

All changes are deferred until the main form's Save button is clicked, same as today.

### Common Workflows

**"I only know it's in Mexico":** Click Mexico → turn on country-level toggle → close panel. One row stored.

**"It's in 45 of 51 US states":** Click US → leave country toggle off → click "Select all" → uncheck 6 states → close panel. 45 exact rows stored.

**"It's in Mexico, confirmed in Oaxaca":** Click Mexico → turn on country-level toggle → check Oaxaca → close panel. Two rows stored: one country-level MX, one exact MX-OAX.

## Admin Gall-Host Exclusion Page — Country Drill-Down

Same drill-down pattern, simplified for exclusions.

### Hemisphere View

The map shows the computed gall range (union of host ranges minus exclusions):
- Green: exact host range states
- Light green: inherited from country-level host range
- Red: excluded states (admin view only)

**Click interactions:**
- Click a **country with subdivisions** → opens exclusion panel, map zooms in
- Click a **leaf country** → toggles exclusion directly
- Click a **state/province** → toggles exclusion directly, same as today

### Country Exclusion Panel

**Header:** Country name and close/back button.

**No country-level toggle.** Exclusions are always exact.

**Subdivision checkbox list:** Each state/province has a checkbox.
- Checked = excluded (red on map)
- Unchecked = not excluded (green or light green depending on host range precision)

**Bulk buttons:** "Exclude all" / "Include all."

Host range data displayed in the panel is read-only context. Only exclusions are editable.

## Public Display

### Terminology and Colors

| Color | Hex | Hover tooltip | Legend label |
|-------|-----|---------------|--------------|
| Green | #228B22 | "California (US-CA) — documented" | Documented |
| Light green | #90EE90 | "Oaxaca (MX-OAX) — country-level record only" | Country-level record only |
| White | #FFFFFF | "Arizona (US-AZ) — not reported" | (not shown in legend) |

**No red on public pages.** Exclusions are applied server-side — excluded states are subtracted from the range data before sending to the client. They appear white like any other not-in-range state.

### Place Detail Pages

Blue highlight (#3B82F6) for geographic membership. Hover shows name and code only, no range language. (Already implemented.)

## ID Tool — Precision-Distinguished Results

When a user filters by place (e.g., "Florida"):

**Query logic:**
- Galls whose hosts have an exact Florida `host_range` row → **documented matches**
- Galls whose hosts have a country-level US `host_range` row → **possible matches**

Both appear in the same results list. Possible matches are styled with a badge (small pill, e.g., "country-level") that has a hover tooltip explaining: "This gall occurs on hosts with country-level US records — state-level data unavailable."

**Implementation:** The current `apply_place_filter` in `Galls.Identification` joins on place hierarchy without distinguishing precision. It needs to tag results based on whether the matching `host_range` row is `exact` for the selected place or `country` for an ancestor place.

When no place filter is selected, no distinction is needed — all results shown normally.

## Migration Plan

### Database

- Remove `continent` from `@valid_precisions` in `HostRange` and `GallRangeExclusion` schemas
- Verify no existing rows use `precision = "continent"` (there shouldn't be any — the column was just added with default `"exact"`)

### What Changes Where

| Component | Change |
|-----------|--------|
| `HostRange` schema | Remove `continent` from valid precisions |
| `GallRangeExclusion` schema | Remove `continent` from valid precisions |
| `Ranges` context | Update `split_by_precision` to handle only `exact` and `country`; update `update_host_places` to accept precision-aware entries from admin form |
| Admin host form | Replace flat code list with precision-aware state; add country drill-down panel as LiveComponent; update save logic to persist precision |
| Admin gall-host page | Add exclusion drill-down panel; update save logic |
| JS `RangeMap` hook | Add country click handler that pushes `drill_down_country` event; support zoom-to-country and zoom-back |
| Public host/gall pages | Update hover tooltip text; update legend text |
| `Galls.Identification` | Tag results with match quality based on precision of matching `host_range` row |
| ID LiveView | Add badge styling for country-level matches |
| Country drill-down panel | New LiveComponent: country toggle, checkbox list, select/deselect all, map sync |

### Existing Behavior Preserved

- The `host_covers_place?` hierarchy logic continues to work for place-based queries
- All existing `host_range` rows have `precision = "exact"` and continue to behave identically
- Public pages that don't show exclusions continue to not show them
- The gall range formula (union of hosts minus exclusions) is unchanged
