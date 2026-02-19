---
status: done
effort: 3-5 days
created: 2026-02-13
updated: 2026-02-18
epic: geo-expansion
blocks: [1db6, 95d7]
---

# Maps rework

## Current State

D3.js + SVG choropleth rendering a static TopoJSON file (usa-can-topo.json, 198KB). geoConicEqualArea projection hardcoded for US/Canada. ~65 polygons (states + provinces). Thumbnail + expandable modal with zoom/pan. Admin edit mode: click to toggle regions. Data model: place table + host_range (where hosts exist) + gall_range_exclusion (where galls don't occur despite hosts). Gall range = union of host ranges minus exclusions.

A tileserver-gl service (gftiles.fly.dev) exists from V1 but was never integrated. Its build script already processes Natural Earth data for the full Western Hemisphere but only includes subdivisions for USA, CAN, MEX, BRA.

## Why Rework

The current D3/SVG approach cannot scale to hemisphere display (500+ subdivisions at varying sizes), cannot support zoom-dependent layer switching (countries at wide zoom, subdivisions when zoomed in), and cannot support future overlay layers (observation data, phenology).

## Research Findings

Surveyed GBIF, iNaturalist, Map of Life, NatureServe, and BONAP. NatureServe is the closest analog to our data model (range = set of admin regions). Their key UX pattern: zoom-dependent layer switching — show broad units at wide zoom, finer units appear as you zoom closer. BONAP's approach (render all ~3,100 counties at once) is the cautionary tale — breaks at hemisphere scale.

## Architecture Decision: MapLibre GL JS + PMTiles

MapLibre GL JS replaces D3 as the rendering engine. Key reasons:
- WebGL handles hundreds of polygons without SVG performance issues
- Native zoom-dependent styling (countries at hemisphere zoom, subdivisions when zoomed in)
- Native multi-layer support for future overlays
- PMTiles (single static file on S3, HTTP range requests) eliminates the need for a tile server

### Forward-compatible layer model

Must not block future observation and phenology overlays. Architecture:

```
S3 (static files)
├── boundaries.pmtiles      ← admin boundaries (choropleth) — Phase 1
├── observations.pmtiles    ← iNat observation density — future
└── phenology.pmtiles       ← seasonal data — future
```

MapLibre renders each as an independent toggleable layer. Precomputed static assets, no real-time tile generation needed. The gftiles service becomes unnecessary.

## UX Pattern

- Hemisphere zoom: countries colored by presence (any subdivision in range → country lit up)
- Zoom in: subdivisions appear with per-subdivision coloring
- Click country to zoom-to-fit
- Hover tooltips with region name + status
- Admin edit mode: click subdivisions to toggle in/out of range
- Future: toggle observation overlay, phenology overlay

## Data Requirements

- Natural Earth 10m Admin-0 (countries) and Admin-1 (states/provinces) for ALL Western Hemisphere countries
- Current build script only has subdivisions for 4 countries — needs expansion to all ~35
- Boundary data encoded via tippecanoe into PMTiles with zoom-dependent simplification
- Place table needs new entries for all WH subdivisions with ISO-3166-2 codes

## Open Questions

- Do all WH countries have usable state/province-level boundaries in Natural Earth? Need to verify coverage.
- How to handle territories and dependencies (Puerto Rico, French Guiana, etc.) — some are Admin-0, some Admin-1
- Caribbean island nations may be too small for subdivision display — country-level may be sufficient for some
- Admin editing UX at subdivision level for unfamiliar geographies — does click-to-toggle still work?

## Data Coverage Analysis (2026-02-18)

### Current: 69 places (US + Canada only)
- 1 continent (North America), 2 countries, 52 states, 14 provinces
- 30,609 host_range rows across 1,576 species
- Saint Pierre & Miquelon is orphaned (no parent in place_hierarchy)

### Expansion target: ~530 places
- ~35 new countries, ~430 new subdivisions, new continent + region entries
- Natural Earth 10m Admin-1 covers all WH sovereign countries with ISO 3166-2 codes (nearly complete since NE v4.0)
- Build script already handles missing codes: COALESCE(iso_3166_2, adm1_code)

### Place hierarchy model

```
Western Hemisphere (region)
├── North America (continent)
│   ├── United States (country) → 52 subdivisions
│   ├── Canada (country) → 13 subdivisions
│   └── Mexico (country) → 32 subdivisions
├── Central America (region)
│   ├── Belize → 6, Costa Rica → 7, El Salvador → 14
│   ├── Guatemala → 22, Honduras → 18, Nicaragua → 17, Panama → 14
├── Caribbean (region)
│   ├── Cuba → 16, Dominican Republic → 32, Haiti → 10
│   ├── Jamaica, Trinidad & Tobago, Bahamas (country-level only)
│   ├── Small island nations (country-level only): AG, BB, DM, GD, KN, LC, VC
│   └── Territories (country-level only): PR, VI, VG, KY, TC, BM, AW, CW, etc.
├── South America (continent)
│   ├── Argentina → 24, Bolivia → 9, Brazil → 27, Chile → 16
│   ├── Colombia → 33, Ecuador → 24, Guyana → 10, Paraguay → 18
│   ├── Peru → 26, Suriname → 10, Uruguay → 19, Venezuela → 25
└── ~494 subdivisions total with meaningful display
```

Regions are useful for filtering/browsing, not just hierarchy. Central America and Caribbean use type=region.

### Display tiers
- **Subdivisions** (~494): All N/C/S American countries + Cuba, DR, Haiti
- **Country-level only**: Small Caribbean islands (<5,000 km²), all territories
- Threshold: anything smaller than a single US county gets country-level treatment

### Gotchas to address
- French overseas territories (GF, GP, MQ) appear as Admin-1 under France in NE — filter by geometry/ISO, not country name
- Panama's 4 indigenous comarcas — verify presence in NE Admin-1
- Fix existing orphan: Saint Pierre & Miquelon has no parent in place_hierarchy
- place.type schema allows: continent, country, region, state, province, county, city — no changes needed

## Sequencing Decision (2026-02-18)

Maps rework happens FIRST, against existing US/Canada data (69 places). Validate MapLibre UX works before expanding the place table. Place expansion is a separate, larger effort that follows.

## Hierarchy Model Correction

Four peer continents, all type=continent. No Western Hemisphere umbrella.

```
North America (continent)
├── United States (country) → 52 subdivisions
├── Canada (country) → 13 subdivisions  
├── Mexico (country) → 32 subdivisions

Central America (continent)
├── Belize, Costa Rica, El Salvador, Guatemala, Honduras, Nicaragua, Panama

Caribbean (continent)
├── Cuba → 16, Dominican Republic → 32, Haiti → 10
├── Small islands (country-level only)

South America (continent)
├── Argentina, Bolivia, Brazil, Chile, Colombia, Ecuador, etc.
```

## Hierarchy Update

Add Western Hemisphere as a region umbrella above the four continents, to support future expansion (Eastern Hemisphere, Holarctic, Palearctic, etc.).

```
Western Hemisphere (region)
├── North America (continent)
├── Central America (continent)
├── Caribbean (continent)
├── South America (continent)
```

Region type already valid in the schema. One extra row, zero code impact.

## Implementation Plan (2026-02-18)

**Branch**: `maps-rework`

### Step 1: Rework Build Pipeline

Strip `services/tileserver-gl/` down to a build script. Remove the tile server — serving static files, not running a service.

**Remove**: `tileserver-gl.Dockerfile`, `fly.toml`, `Makefile`, `boundaries.mbtiles`

**Keep & modify**: `build_boundaries.sh`
- Output format: `.pmtiles` instead of `.mbtiles` (tippecanoe supports this directly)
- Expand `STATE_COUNTRIES` to all WH countries (the `COUNTRIES` array already lists them all)
- Two source layers in the output:
  - `countries` — Admin-0 polygons with ISO alpha-2 `code` property
  - `subdivisions` — Admin-1 polygons with ISO 3166-2 `code` property
- Output to `priv/static/data/boundaries.pmtiles`
- Handle French overseas territory gotcha (filter by geometry, not country name)

**Rename directory**: `services/tileserver-gl/` → `services/boundaries/` (or similar)

**Result**: Single `boundaries.pmtiles` with all WH countries + subdivisions, served as a static asset. Full hemisphere geometry but range data still only covers US/Canada — tests zoom-dependent UX without expanding place table.

### Step 2: Frontend Dependencies

**Add**: `maplibre-gl` (npm), `pmtiles` (npm)

**Remove** (after step 3): `d3-geo`, `d3-zoom`, `d3-selection`, `topojson-client`

**CSS**: Import `maplibre-gl/dist/maplibre-gl.css` via JS import (esbuild sidecar) or layout head link.

### Step 3: New MapLibre Hook

Replace `assets/js/hooks/range_map.js` with MapLibre-based implementation.

**Global setup** (app.js): Register PMTiles protocol once, not per hook.

**Hook lifecycle**:
- `mounted()`: Create MapLibre map. Read data attributes: `data-in-range`, `data-excluded-range`, `data-editable`, `data-tiles-url`.
- `handleEvent('range-update', ...)`: Update choropleth colors without recreating map.
- `destroyed()`: Call `map.remove()` for cleanup.
- Use `phx-update="ignore"` — MapLibre owns its DOM.

**Layers**:
- `countries-fill`: Zoom 0–4. Green if ANY subdivision in that country is in range.
- `subdivisions-fill`: Zoom 4+. Per-subdivision coloring from in_range/excluded_range sets.
- `countries-line` / `subdivisions-line`: Border strokes, zoom-dependent width.

**Interactions**:
- Hover: MapLibre Popup (no close button, follows cursor) — region name + code + status.
- Click (public): `fitBounds` to zoom into clicked country/region.
- Click (admin/editable): `pushEvent('toggle_region', {code})` — same event contract as today.

**Coloring**: Green (in range), coral (excluded), white (default). `match` expression against code sets.

**Thumbnail + modal**: Inline interactive map at fixed size — MapLibre has native zoom/pan so modal pattern likely unnecessary. Revisit if inline size feels too constrained.

### Step 4: Component Update

Update `data_display_components.ex` `range_map` component:
- Add `tiles_url` attribute (default `/data/boundaries.pmtiles`, configurable for future S3)
- Add `phx-update="ignore"` to container div
- Keep same public API: `in_range`, `excluded_range`, `editable`, `id`
- Remove inline SVG rendering — hook handles everything

### Step 5: Verify Feature Parity

Against existing US/Canada data:
- Public gall page: range map displays correctly
- Public host page: range map displays correctly
- Admin host form: click-to-toggle works, select all/deselect all works
- Admin gall host: exclusion display works
- ID tool: place filter functions (uses place data, not map component)
- Hemisphere zoom shows WH country outlines (no range data for non-US/CA)

### Step 6: Cleanup

- Remove `priv/static/data/usa-can-topo.json` (and `.gz`)
- Remove old D3 npm packages
- Decommission `gftiles.fly.dev` Fly app (separate task)
- Update tests referencing old topology file

### Serving Strategy

- **Dev + Prod (initial)**: `priv/static/data/` via Plug.Static (supports HTTP Range requests)
- **Prod (future)**: S3 with CORS for range requests, switch `tiles_url` via config
