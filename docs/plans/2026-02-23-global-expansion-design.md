# Global Expansion Design

## Vision

Expand gallformers.org from Western Hemisphere coverage to the entire world. The geographic infrastructure (places, tiles, maps, continent selector) ships complete. Gall and host data populates organically as researchers contribute from their regions.

**Target milestone:** Announce global coverage at the Romania gall conference, summer 2026.

## Guiding Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Rollout model | Infrastructure-first, data-organic | Data will always be patchy outside NA. Ship the global map and let it fill in. |
| Territory classification | Pure geography, not politics | Réunion → Africa, not France. Ecology, not sovereignty. Consistent with WH approach. |
| Disputed territories | Follow Natural Earth defaults | Apply logic when edge cases arise. Don't overthink it. |
| Subdivision scope | Curated by ecological relevance | Most countries of meaningful size get subdivisions. Exceptions for smaller countries in Africa, Asia, Europe where it doesn't add value. |
| User region preference | localStorage, sticky continent selector | No accounts needed. Persists across sessions. Scopes ID tool at minimum. |
| Host plant data | WCVP (already global) | Pipeline from WH expansion works as-is. No new data sources needed. |

## Work Streams

### Stream 0: Maps & Range Cleanup (b99b)

**Do this first.** Fix all known bugs and code quality issues from the maps-rework assessment before writing any new code. The current codebase has bugs, missing tests, and duplicated logic that would compound under global expansion.

#### Bugs to fix

Already patched (uncommitted on maps-rework branch):
1. `list_places()` vs `list_all_places()` — admin pages used the wrong function, dropping country codes from lookups
2. `split_by_precision` missing `place_id` in select — crashes on country-level precision
3. `get_display_range_for_gall` didn't subtract exclusions from exact codes
4. ExclusionDrillDown checkbox semantics inverted (checked = excluded, should be checked = in range)
5. ExclusionDrillDown showed non-host subdivisions
6. JS click handler re-opened drill-down on subdivision clicks

Still open:
7. `toggle_region` uses expanded `host_places` instead of `host_places_raw` — fragile, works by accident
8. Country-level hover tooltip doesn't check exclusion status in admin mode

#### Code quality improvements

- Deduplicate precision expansion logic (admin page reimplements what `split_by_precision` does)
- Use `Place` schema instead of raw `"place"` table strings in queries
- Extract shared `toggle_exclusion` helper (duplicated 3x in GallHostLive)
- Precompute lookup maps (`code → place`, `id → place`) once in mount, not on every call
- Move `Repo.transaction` from LiveView into Ranges context
- Migrate gall-host page from raw hook div to `range_map` component
- Merge `normalize_place_entries` and `normalize_exclusion_entries` (identical functions)
- Use `MapSet` operations instead of list subtraction in `get_display_range_for_gall`
- Batch `leaf_descendant_ids` queries instead of N+1 per country code
- Add `@impl true` to ExclusionDrillDown callback handlers
- Create a struct for range display data (`%RangeDisplay{in_range, inherited_range, excluded_range}`)

#### Test coverage to add

- `get_display_range_for_gall/1` — primary range computation function, zero tests
- `split_by_precision/1` — country expansion logic, zero tests
- `get_display_range_for_host/1` — zero tests
- `toggle_exclusion_for_gall/2` — zero tests
- ExclusionDrillDown component lifecycle and interactions
- CountryDrillDown interactions (currently 1 test — closed state only)
- Gall range queries (`get_places_for_gall`, etc.)
- Host toggle operations
- Admin page range toggle assertions (currently smoke-only)
- Drill-down workflow integration tests
- Exclusion fixtures in test seeds

### Stream 0.5: Browse/Search Continent Scoping — Design Pass

**Research and design only, no code.** Analyze how continent-level scoping would affect the Browse and Search pages. Produce a recommendation before starting infrastructure work, in case it surfaces data model or architectural requirements that affect Streams 1-4.

Questions to answer:
- Does the Browse page need continent scoping, or is it already navigable enough?
- Does Search need scoping, or should it always be global with results annotated by region?
- If scoped, does it use the same sticky continent selector as the ID tool?
- Are there any data model implications (e.g., need continent IDs in denormalized places for query performance)?
- Does this affect the place hierarchy design or the continent selector component?

### Stream 1: Place Data Expansion

Add all remaining countries and subdivisions to the database.

**Continents to add:** Europe, Africa, Asia, Oceania. Keep existing: North America, Central America, Caribbean, South America.

**Top-level hierarchy change:** Replace "Western Hemisphere" region with continents as the top-level grouping (or add a "World" root — TBD during implementation). Continents become the unit that the sticky selector operates on.

**Country scope:** All ~195 sovereign nations plus ecologically-distinct overseas territories, classified by geographic continent:
- Réunion → Africa
- French Polynesia → Oceania
- Faroe Islands → Europe
- Hong Kong, Macau → Asia
- etc.

European parent countries (France, UK, Netherlands, Denmark) exist as European countries. Their overseas territories are independent entries under their geographic continent. No parent-child link between sovereign nation and overseas territory.

**Subdivision scope:** Curated by ecological relevance and country size. Subdivision candidates include most countries of meaningful size and ecological diversity. Smaller or ecologically uniform countries are leaf nodes. The exact list is a curation task during implementation — expect 60-80+ countries with subdivisions (up from 26 in WH), yielding roughly 2500-3500 total places.

**Implementation:** Ecto migration, same pattern as `20260219140816_add_western_hemisphere_places.exs`. Source data from Natural Earth plus ISO 3166-2 for subdivision codes.

### Stream 2: Tile Generation

Expand `build_boundaries.sh` from Western Hemisphere to global scope.

**Changes:**
- Remove the Western Hemisphere country filter from `COUNTRIES` array — include all countries
- Extend `STATE_COUNTRIES` to match the curated subdivision list
- Add more entries to `SUBUNIT_SU_A3` arrays for global French/British/Dutch territories
- Add extraction logic for any territories that don't appear in Natural Earth's standard layers (same patterns already solved for GF/GP/MQ/BQ)
- Update `verify_tiles.py` to validate against the full place table

**Tile size:** Expect growth from ~2MB to ~8-15MB. PMTiles is designed for this scale — no architectural concern.

**Territory edge cases to investigate during implementation:**
- French overseas departments beyond the WH (Réunion, Mayotte, New Caledonia, French Polynesia, Wallis & Futuna, Saint Barthélemy, Saint Martin)
- British Overseas Territories (Gibraltar, St. Helena, Pitcairn, etc.)
- Special Administrative Regions (Hong Kong, Macau)
- Microstates that may not have clean Natural Earth polygons

### Stream 3: Map JS Updates

**Changes to `range_map.js`:**
- Remove `maxBounds: [[-180, -62], [10, 86]]` — allow full globe view
- Adjust default center/zoom for world view (or better: default to the user's sticky continent)
- Test `fitToRange` with global data — the `querySourceFeatures` approach may need adjustment since it only sees loaded tiles in the viewport
- Performance validation with ~4500 polygons (should be fine with vector tiles but verify)

**Map UX considerations:**
- Default view when no range data: show the user's selected continent, not the whole world
- Species with range data: `fitToRange` zooms to where the data is (existing behavior, works globally)
- Empty state: consider adding "No range data available" text (currently just shows blank map)

### Stream 4: Continent Selector

A sticky, localStorage-backed continent preference that scopes the user's experience.

**Behavior:**
- Always set after first visit — first-time visitors pick their continent
- Stored in localStorage, persists across sessions and page loads
- Scopes the ID tool immediately (required for launch)
- Browse/Search scoping determined by Stream 0.5 design pass
- User can temporarily override for a single search/ID session without changing the sticky preference
- Changing the sticky preference is always available (settings, header UI, or similar)

**Continent options:** Match the continent records in the place table — North America, Central America, Caribbean, South America, Europe, Africa, Asia, Oceania. Possibly group into fewer options if the list feels long (e.g., "Americas" combining NA/CA/Caribbean/SA) — TBD during implementation.

**ID tool integration:**
- Place typeahead only shows places within the selected continent
- ID results filtered to galls whose host ranges overlap the selected continent
- Existing place filter becomes a sub-filter within the continent scope

**Individual species/gall pages:** Always show full global range regardless of continent preference. The selector scopes discovery, not data display.

## Not In Scope

- **User accounts** — localStorage handles the region preference. Accounts (matter 0fc6) are a separate effort.
- **UI localization** — English stays. Local common names supported as data (aliases).
- **Bulk data import** — Data grows organically through admin workflows.
- **Eastern Hemisphere host data sourcing** — WCVP is already global. No new pipelines needed.

## Open Questions

- **Continent grouping for selector:** Should the 8 continents be presented as-is, or grouped (e.g., "Americas" as one option)? Depends on how the ID tool filtering feels in practice.
- **Browse/Search scoping:** Deferred to Stream 0.5 design pass. May affect nothing, or may require the continent selector to be site-wide from day one.
- **Subdivision curation list:** Exact countries TBD during Stream 1. Need to balance completeness against Natural Earth data quality per country.
- **First-visit experience:** How to prompt continent selection — modal, landing page interstitial, or inline in the ID tool?
- **Map default view:** When no species range is shown, center on the user's continent or show the whole world?

## Dependencies

- **b99b cleanup (Stream 0) must complete before any new work.** The current maps-rework branch has bugs and code quality issues that would compound.
- **Stream 0.5 must complete before Streams 1-4 begin** in case Browse/Search scoping has architectural implications.
- **Stream 1 (places) gates Stream 2 (tiles)** — tiles validate against the place table.
- **Stream 2 (tiles) gates Stream 3 (map JS)** — need global tiles to test against.
- **Stream 4 (continent selector) can parallel Streams 1-3** — it's a UI/UX concern independent of the geographic data pipeline.

## Relationship to Existing Matters

- **1db6 (Western Hemisphere expansion)** — This supersedes the geographic scope. WH infrastructure work is the foundation we're building on. 1db6 can be closed when this ships.
- **7932 (Host plant data sourcing)** — WCVP pipeline extends naturally to global. No additional work needed.
- **e617 (WCVP live lookup)** — Already global. No changes needed.
- **b99b (Maps assessment)** — Rolled into Stream 0 of this effort.
- **0f79 (ID tool V2)** — The continent selector is a step toward rethinking the ID tool. This work informs but doesn't replace that matter.
