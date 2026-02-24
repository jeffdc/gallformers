# Place Hierarchy & Range Precision Design

**Date:** 2026-02-19
**Branch:** maps-rework
**Related matters:** 95d7 (place table expansion), 554e (public place browse), 67e0 (admin places redesign)

## Problem

The place table expanded from ~69 US/CA entries to 567 Western Hemisphere places with a full hierarchy (region → continent → country → subdivision). The existing range model and UI assume a flat list of states/provinces. This breaks down in several ways:

- "This plant occurs in all of Brazil" requires selecting 27 individual states
- "This plant occurs across South America" is worse — hundreds of clicks
- Non-subdivided entities (Greenland, Bahamas) don't appear in the ID tool's place filter
- No way to record imprecise range data ("somewhere in Brazil, don't know which states")
- The ID tool filter has no notion of hierarchy

## Design Decisions

Captured through collaborative brainstorming:

1. **Both "all of Brazil" and "somewhere in Brazil" are valid** — the data model must support ranges at any hierarchy level while preserving the precision signal
2. **ID tool filtering is inclusive with indicators** — a country-level range shows up when filtering by a child state, marked as coarser data
3. **Admin map interaction** — click to drill into country subdivisions, shift+click to select the whole country
4. **Non-subdivided entities are leaf nodes** — Bahamas is a leaf country, Greenland is a leaf country (not a subdivision of Denmark, since Denmark isn't in the Western Hemisphere)
5. **US territories reclassified** — Puerto Rico and US Virgin Islands become Caribbean countries, not US subdivisions. "All of US" means 50 states + DC.
6. **Hawaii stays as a US state** — ecologically unusual but politically unambiguous
7. **Approach A chosen** — hierarchy-aware ranges with recursive CTEs, not materialized expansion or dual-layer tables. SQLite 3.43.2 supports WITH RECURSIVE. Dataset is small (567 places, max depth 4).
8. **No continents in the ID tool typeahead** — too broad for identification. Backend supports it if needed later.
9. **PostgreSQL migration (matter 4474) is independent** — this design ships on SQLite. Postgres could later add ltree for faster hierarchy queries, but it's an optimization not a requirement.

## Section 1: Data Model Changes

### `host_range` — add precision column

```sql
ALTER TABLE host_range ADD COLUMN precision TEXT NOT NULL DEFAULT 'exact'
  CHECK (precision IN ('exact', 'country', 'continent'));
```

- `'exact'` — admin selected this specific place (all existing rows)
- `'country'` — admin selected a country; specific subdivisions unknown
- `'continent'` — admin selected a continent; specific countries/subdivisions unknown

The `place_id` foreign key points to whatever level the admin selected. A "Brazil, precision=country" row has `place_id` pointing to the Brazil place record.

### `gall_range_exclusion` — same treatment

```sql
ALTER TABLE gall_range_exclusion ADD COLUMN precision TEXT NOT NULL DEFAULT 'exact'
  CHECK (precision IN ('exact', 'country', 'continent'));
```

An exclusion at country level means "this gall is excluded from this entire country." An exclusion at exact level means "excluded from this specific state."

### No changes to `place` or `place_hierarchy`

The hierarchy tables are correct as-is.

### Territory reclassification

Puerto Rico: update the existing `US-PR` row in-place — change code to `PR`, type to `country`, rewire hierarchy from US to Caribbean (`XB`). Delete the unused duplicate country entry. The 86 host_range rows don't move — their place_id still points at the same row.

US Virgin Islands: already correct as a country under Caribbean with code `VI`. No changes needed.

## Section 2: Hierarchy Queries

### Recursive descendant expansion

Given a place_id, find all descendant place_ids:

```sql
WITH RECURSIVE descendants(id) AS (
  SELECT :place_id
  UNION ALL
  SELECT ph.place_id
  FROM place_hierarchy ph
  JOIN descendants d ON ph.parent_id = d.id
)
SELECT id FROM descendants;
```

### Recursive ancestor expansion

Given a place_id, find all ancestor place_ids:

```sql
WITH RECURSIVE ancestors(id) AS (
  SELECT :place_id
  UNION ALL
  SELECT ph.parent_id
  FROM place_hierarchy ph
  JOIN ancestors a ON ph.place_id = a.id
)
SELECT id FROM ancestors;
```

Both verified against production data — California correctly returns US → North America → Western Hemisphere as ancestors; Brazil correctly returns all 27 states as descendants.

### Ecto integration

Functions in the `Places` context:

```elixir
def descendant_ids(place_id)  # place + all children recursively
def ancestor_ids(place_id)    # place + all parents recursively
```

Implemented as raw SQL fragments via `Ecto.Query.fragment`.

### ID tool filter logic

When user selects a place:

1. Get the selected place and all its **descendants** (user picks "Brazil" → include all Brazilian states)
2. For each candidate gall, check if any host has a `host_range` row where:
   - `place_id` is in the descendant set (exact match at or below selected level), OR
   - `place_id` is an **ancestor** of the selected place (country/continent-level range covering the area)
3. Tag results with match precision — "exact" if matched at or below selected level, "inherited" if matched via ancestor

### Gall range exclusion logic

Same bidirectional expansion:
- Exclusion at country level excludes all descendants
- Exclusion at state level excludes only that state
- Check: is the place itself excluded, OR is any ancestor excluded?

### Optional future optimization

Cache ancestor chains at app startup: `place_id → [ancestor_ids]`. 567 places x max 4 ancestors = trivial memory. Eliminates recursive CTE from hot-path queries. Not needed for v1.

## Section 3: Admin UX — Range Assignment

### Map interaction model

| Action | Behavior |
|--------|----------|
| **Click a country** | Zoom/drill into it, show subdivisions for individual selection |
| **Shift+click a country** | Select entire country as one unit (precision=`'country'`). All subdivisions highlight green. |
| **Click a subdivision** | Toggle that specific subdivision (precision=`'exact'`), same as today |
| **Click a leaf country** (Bahamas, Greenland) | Toggle directly (precision=`'exact'`), behaves like clicking a state |

Tooltip on country hover for discoverability: "Click to browse states · Shift+click to select all of [country]"

### Sidebar range summary

Show selected ranges grouped by precision:

```
Range:
  Country-level: Brazil, Colombia
  Exact: US-CA, US-TX, US-OR, MX-JAL
```

Country-level entries get two actions:
- **Expand** — converts single country row to individual state rows (all marked `'exact'`). One-way refinement.
- **Remove** — deselects the whole country.

### Map coloring for mixed precision

- Country-level range: all subdivisions show green with a subtle hatch/stripe pattern to distinguish from exact
- Exact range: solid green, same as today
- Admin exclusions: light red, same as today

### LiveView events

```
toggle_region(code)           — existing, exact subdivision click
toggle_country(code)          — shift+click on country (precision='country')
expand_country(code)          — sidebar action, convert country→individual states
drill_into_country(code)      — zoom map into country's subdivisions
```

## Section 4: ID Tool — Place Filter UX

### Grouped typeahead

Single input, results grouped by level. Typing "br" shows:

```
Countries
  Brazil (South America)

States & Provinces
  British Columbia (Canada)
  Brasília (Brazil)
```

Typing "bah" shows:

```
Countries
  Bahamas (Caribbean)
```

### Selection behavior

| Selection | Filter behavior |
|-----------|----------------|
| A **state/province** (leaf) | Filter to galls with hosts in that exact place, plus hosts with ancestor-level ranges covering it. Ancestor matches shown with indicator. |
| A **leaf country** (Bahamas) | Same as selecting a state — it IS the leaf. |
| A **subdivided country** (Brazil) | Filter to galls with hosts in any Brazilian state OR hosts with a country-level Brazil range. |

### Precision indicator in results

Galls matched via ancestor-level range (not exact place match) get a visual badge:

```
Andricus quercuscalifornicus          ← host confirmed in US-CA
Dryocosmus kuriphilus      ⓘ country  ← host reported in "United States"
```

Badge communicates: "this gall's host is reported at the country level — state-level data not confirmed."

### Search function

New `Places.search_places/2` replaces `search_subdivision_places/2`:
- Returns countries + states/provinces (not continents/regions)
- Includes parent name for context display
- Returns a `group` field for typeahead grouping
- Ordered: countries first, then subdivisions, alphabetical within each

### URL parameter

No change — `pl=US-CA` stays the same. The backend determines expansion based on the place's level in the hierarchy.

## Section 5: Public Species Pages — Range Display

### Map coloring

| Range type | Color | Meaning |
|-----------|-------|---------|
| Exact subdivision | Solid green | Host confirmed in this specific state |
| Inherited from country | Green with hatch/stripe | Host reported at country level, not state-specific |
| Excluded (admin only) | Light red | Gall excluded from this place |
| No data | White | No range information |

### Range text summary

Below the map:

```
Range:
  United States: California, Oregon, Texas
  Brazil (country-level)
  Colombia (country-level)
```

### Tooltip on hover

- Exact range: "São Paulo — host confirmed"
- Inherited from country: "São Paulo — reported in Brazil (state not confirmed)"
- No range: "São Paulo — not reported"

### Unchanged

- `fitToRange()` auto-zoom computes bounds from all green features regardless of precision
- PMTiles layer structure stays the same
- Non-editable maps don't show exclusions

## Section 6: Data Migration

Single migration file:

1. Add `precision` column to `host_range` (default `'exact'`)
2. Add `precision` column to `gall_range_exclusion` (default `'exact'`)
3. Reclassify Puerto Rico: update existing row (`US-PR` → `PR`, type `state` → `country`), rewire hierarchy to Caribbean, delete duplicate country entry
4. No PMTiles rebuild needed — PR and VI codes now match between tiles and DB

## Section 7: Grouped Typeahead Component Enhancement

### New optional `group_key` attribute

```elixir
<.typeahead
  id="place-picker"
  query={@place_query}
  results={@place_results}
  selected={@selected_place}
  search_event="search_place"
  select_event="select_place"
  clear_event="clear_place"
  group_key={:group}             # optional, enables grouping
/>
```

When `group_key` is set:
- Results rendered in arrival order (backend controls sort)
- Non-selectable header row inserted when group value transitions
- Headers styled as muted, smaller text
- Keyboard navigation skips headers
- ARIA: headers get `role="presentation"`, items keep `role="option"`

When `group_key` is not set: component behaves exactly as today. No breaking change.

### Result shape

```elixir
[
  %{id: 42, name: "Brazil", description: "South America", group: "Countries"},
  %{id: 301, name: "British Columbia", description: "Canada", group: "States & Provinces"}
]
```

The `description` field provides parenthetical context. The existing `.typeahead` already supports description display.

### Scope

~15 lines of template changes, ~5 lines of JS hook changes. Every other typeahead in the app is unaffected.
