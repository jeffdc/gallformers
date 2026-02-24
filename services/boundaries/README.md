# Boundary Tiles Pipeline

Generates PMTiles vector tiles for the range map component from Natural Earth shapefiles.

## Quick Reference

```bash
# Rebuild the tiles (takes ~2 minutes)
cd services/boundaries
./build_boundaries.sh ../../priv/static/data/boundaries.pmtiles

# Hard refresh the browser (Cmd+Shift+R) to pick up new tiles
```

### Prerequisites

```bash
brew install gdal tippecanoe curl unzip jq
```

## Pipeline Overview

```
Natural Earth 10m shapefiles (remote, cached locally)
    │
    ├─ 10m_cultural.zip → Admin-0 countries, Admin-1 states/provinces
    └─ 10m_physical.zip → Lakes
    │
    ↓  ogr2ogr: extract and filter, add `code` property
    │
    ├─ countries shapefile     → countries GeoJSON
    ├─ subdivisions shapefile  → subdivisions GeoJSON
    ├─ lakes shapefile         → lakes GeoJSON
    └─ (jq)                   → non_subdivided GeoJSON
    │
    ↓  tippecanoe: encode all layers into single PMTiles file
    │
    priv/static/data/boundaries.pmtiles
    │
    ↓  Phoenix static plug serves to browser
    │
    assets/js/hooks/range_map.js (MapLibre GL JS)
```

## Files

| File | Purpose |
|------|---------|
| `services/boundaries/build_boundaries.sh` | One-shot tile generator script |
| `services/boundaries/extract_places.sh` | Generates `global_places.json` for DB seeding (not tiles) |
| `services/boundaries/verify_tiles.py` | Verifies PMTiles coverage against the place database |
| `services/boundaries/inspect_tile.py` | Finds where a specific place code appears in tiles |
| `services/boundaries/inspect_natural_earth.py` | Searches Natural Earth layers for a territory |
| `services/boundaries/PLACE_REFERENCE.md` | Canonical reference of all expected places and tile coverage |
| `priv/static/data/boundaries.pmtiles` | Output: vector tiles (~370MB on disk, served via HTTP range requests — browsers fetch only the tiles needed for the current viewport, typically a few hundred KB) |
| `assets/js/hooks/range_map.js` | MapLibre GL JS hook that consumes the tiles |
| `lib/gallformers/places.ex` | Places context — range queries, hierarchy traversal |
| `lib/gallformers/places/place.ex` | Place schema (id, name, code, type) |
| `~/.cache/naturalearth/` | Cached Natural Earth zip downloads |

## PMTiles Layers

The output file contains three named vector tile layers:

| Layer | Source Data | `code` Property | Used For |
|-------|------------|-----------------|----------|
| `countries` | NE Admin-0 | ISO alpha-2 (`US`, `BR`, `GL`) | Country fills + borders |
| `subdivisions` | NE Admin-1 + non-subdivided countries | ISO 3166-2 (`US-SD`, `BR-AM`) or alpha-2 for leaf territories (`PR`, `GL`) | Choropleth fills, click/hover targets |
| `lakes` | NE Lakes (scalerank < 2, clipped to hemisphere) | none | Blue overlay for Great Lakes etc. |

### The `code` Property

The `code` property is the stable identifier that links tile features to database `place.code` values. It is NOT a native Natural Earth field — it is synthesized during the build:

- **Countries**: `CASE WHEN ISO_A2 != '-99' THEN ISO_A2 ELSE SUBSTR(ADM0_A3, 1, 2) END`
- **Subdivisions**: `COALESCE(iso_3166_2, adm1_code)`

The fallbacks handle territories where Natural Earth sets `ISO_A2` to `-99` (e.g., some French overseas territories).

### Non-Subdivided Countries

Countries/territories without admin-1 subdivisions in Natural Earth (e.g., Puerto Rico, Bermuda, Greenland, Bahamas) need special handling. Their country polygons are copied into the `subdivisions` layer so the JS click handler can treat everything uniformly. The jq filter in the build script excludes countries listed in `STATE_COUNTRIES` (those that DO have subdivisions). Countries are included in `STATE_COUNTRIES` if they have more than 3 admin-1 subdivisions in Natural Earth — this threshold ensures only meaningfully subdivided countries get detailed tiles.

## Build Script Internals

### Country Lists

The script maintains two arrays:

- **`COUNTRIES`**: All countries worldwide except Antarctica. Uses ISO 3166-1 alpha-3 codes. Dynamically derived from Natural Earth data.
- **`STATE_COUNTRIES`**: Subset of `COUNTRIES` that have meaningful admin-1 subdivisions (>3 subdivisions in Natural Earth). Dynamically derived. Countries NOT in this list get their polygons merged into the `subdivisions` layer.

### Processing Steps

1. **Download**: Fetch Natural Earth 10m cultural + physical zips (cached in `~/.cache/naturalearth/`)
2. **Extract**: Unzip to temp directory
3. **Filter countries**: ogr2ogr with SQL WHERE clause on `adm0_a3 IN (...)`, adds `code` property
4. **Filter subdivisions**: ogr2ogr with SQL WHERE on `adm0_a3 IN (STATE_COUNTRIES)`, adds `code` property
5. **Filter lakes**: ogr2ogr scalerank filter, then spatial clip to country boundaries
6. **Convert to GeoJSON**: ogr2ogr shapefile → GeoJSON for each layer
7. **Generate non-subdivided**: jq extracts countries NOT in `STATE_COUNTRIES` from countries GeoJSON, reshapes properties to match subdivision schema
8. **Encode tiles**: tippecanoe combines all GeoJSON files into single PMTiles

### Tippecanoe Flags

```bash
tippecanoe -o output.pmtiles \
    --named-layer=countries:countries.geojson \
    --named-layer=subdivisions:subdivisions.geojson \
    --named-layer=subdivisions:non_subdivided.geojson \  # merged into same layer
    --named-layer=lakes:lakes.geojson \
    --force \
    --minimum-zoom=1 \
    --maximum-zoom=10 \
    --no-feature-limit \       # keep all features at all zoom levels
    --no-tile-size-limit \     # don't drop features to fit tile size
    --detect-shared-borders \  # prevent gaps between adjacent polygons
    --read-parallel
```

Two inputs use `--named-layer=subdivisions:` — tippecanoe merges them into a single layer automatically.

## How LiveViews Consume the Map

The range map is a reusable component defined in `data_display_components.ex` as `.range_map`. It renders a `div` with `phx-hook="RangeMap"` and `phx-update="ignore"` (so LiveView doesn't clobber the MapLibre canvas).

### Data Flow

```
DB (place table, host_range/gall_range_exclusion tables)
    ↓
LiveView (assigns: places, excluded_places, inherited_places)
    ↓
Component data attributes (data-in-range, data-excluded-range, data-inherited-range)
    ↓
JS Hook reads attributes on mount + updated()
    ↓
MapLibre paint expressions color features by matching `code` property against the sets
```

### Modes

- **Editable** (`data-editable="true"`): Admin forms. Click toggles a subdivision, shift+click toggles all subdivisions in a country. Pushes `toggle_region` and `toggle_country` events to the LiveView.
- **Navigable** (`data-navigable="true"`): Public place pages. Click navigates to the place's detail page. Pushes `navigate_to_place` events.
- **Read-only** (neither): Species detail pages. Map is display-only, no click handling.

### Layer Interaction Model

Both `countries-fill` and `subdivisions-fill` layers overlap geographically (subdivisions are drawn on top). A single click fires on BOTH layers if you use per-layer click handlers. The JS uses a single unified `map.on('click', ...)` handler that calls `queryRenderedFeatures` for each layer and applies priority:

1. Shift+click → always `toggle_country` (country code from countries layer)
2. Real subdivision code (contains `-`) → `toggle_region`
3. Bare country code only → `toggle_country` (leaf territory or fallback)

### Choropleth Colors

Both `countries-fill` and `subdivisions-fill` use the same `buildFillExpression()` to color features. The difference is the fallback color:
- `subdivisions-fill`: fallback is white (not in range)
- `countries-fill`: fallback is light gray (neutral land)

This means selected territories (like Puerto Rico) turn green in BOTH layers — the countries layer provides the base, and the subdivisions layer (which includes non-subdivided countries) provides the interactive target.

## Expected Feature Counts

After a successful build, tippecanoe should report approximately:

- **~4,880 features total** (as of Feb 2026)
  - ~249 countries (includes French overseas departments from map_subunits and BES islands from admin-1)
  - ~4,290 subdivisions (from Natural Earth Admin-1)
  - ~86 non-subdivided countries/territories (merged into subdivisions layer)
  - A small number of lakes

If the count is significantly different, something went wrong:
- **Much higher**: The non-subdivided filter isn't excluding STATE_COUNTRIES — check property casing in the jq filter
- **Much lower** (~100-200): tippecanoe is dropping features — check for `--coalesce-densest-as-needed` or other dropping flags

Run `python3 verify_tiles.py` after any rebuild to check for gaps.

## Diagnostic Scripts

Three Python scripts in `services/boundaries/` help debug tile coverage issues. All require `tippecanoe` and/or `gdal` to be installed.

### `verify_tiles.py` — Coverage verification

Compares the PMTiles file against the `place` database table and reports:
- Countries in DB but missing from tiles entirely
- Non-subdivided countries missing from the subdivisions layer
- DB subdivisions missing from tiles (code mismatches)
- Codes in tiles but not in DB (unexpected extras)

```bash
python3 verify_tiles.py                              # defaults: priv/static/data/boundaries.pmtiles + priv/gallformers.sqlite
python3 verify_tiles.py path/to/tiles.pmtiles        # custom PMTiles path
python3 verify_tiles.py tiles.pmtiles db.sqlite      # custom both
```

**Run this after every tile rebuild.** Exit code 0 = all checks pass.

### `inspect_tile.py` — Single place lookup

Finds which tiles contain a specific place code, in which layers, at which zoom levels.

```bash
python3 inspect_tile.py GF      # French Guiana — should be in both countries and subdivisions
python3 inspect_tile.py US-CA   # California — should be in subdivisions only
python3 inspect_tile.py PR      # Puerto Rico — should be in countries + subdivisions (non-subdivided)
```

### `inspect_natural_earth.py` — Source data lookup

Searches all Natural Earth 10m layers (admin_0_countries, admin_0_map_subunits, admin_1_states_provinces) for a given ISO alpha-3 code. Shows which layer the territory lives in and its field values.

```bash
python3 inspect_natural_earth.py KNA    # Saint Kitts and Nevis — in admin_0_countries
python3 inspect_natural_earth.py GUF    # French Guiana — in map_subunits, NOT admin_0_countries
python3 inspect_natural_earth.py BES    # Caribbean Netherlands — in admin_1, NOT admin_0_countries
```

Use this when adding a new territory to find out which NE layer to extract from.

## Adding New Territories

The pipeline now includes all countries globally except Antarctica, so most territories are already covered. However, if you need to add a new territory or verify coverage:

1. **Find the ISO alpha-3 code** for the territory
2. **Run `inspect_natural_earth.py`** to determine which NE layer it appears in:
   - `admin_0_countries` → automatically included
   - `admin_0_map_subunits` → these are extracted separately (check `SUBUNIT_TERRITORIES` array)
   - `admin_1_states_provinces` → some territories exist only as subdivisions (like BES/Caribbean Netherlands)
3. **Check subdivision threshold**: Countries with >3 admin-1 subdivisions are automatically added to `STATE_COUNTRIES`
4. **For subunits NOT in admin_0_countries** (like French overseas departments), verify they're in the `SUBUNIT_TERRITORIES` array
5. **Run `build_boundaries.sh`** to rebuild tiles
6. **Run `verify_tiles.py`** to confirm coverage
7. **Add the place to the database** via migration (with matching `code` value)
8. **Update `PLACE_REFERENCE.md`** with the new entry

## Known Gotchas

### French Overseas Departments and Caribbean Netherlands

Natural Earth does NOT include French Guiana (GUF), Guadeloupe (GLP), or Martinique (MTQ) in `ne_10m_admin_0_countries`. They are classified as "Geo unit" sub-units of France and appear only in `ne_10m_admin_0_map_subunits` with `ADM0_A3 = FRA` and `SU_A3 = GUF/GLP/MTQ`. Their `ISO_A2` values are French departmental codes (`FR-973`, `FR-971`, `FR-972`), not the ISO alpha-2 codes our database uses (`GF`, `GP`, `MQ`).

The build script handles this by extracting these territories from `map_subunits` and assigning the correct alpha-2 codes via the `SUBUNIT_TERRITORIES` and `SUBUNIT_CODE_MAP` arrays.

Similarly, the Caribbean Netherlands (BES — Bonaire, Sint Eustatius, Saba) doesn't appear as a country at all. The three islands are subdivisions of the Netherlands (`adm0_a3 = NLD`) in the admin-1 layer. The build script extracts them and assigns `code = BQ`.

If you add new territories and they don't appear in the tiles, check which NE layer they're actually in:

```bash
# Check admin-0 countries
ogrinfo -q ne_10m_admin_0_countries.shp -sql \
  "SELECT ADM0_A3, NAME FROM ne_10m_admin_0_countries WHERE ADM0_A3 = 'XXX'" -dialect SQLITE

# Check map subunits (French-style overseas departments)
ogrinfo -q ne_10m_admin_0_map_subunits.shp -sql \
  "SELECT SU_A3, NAME, ADM0_A3 FROM ne_10m_admin_0_map_subunits WHERE SU_A3 = 'XXX'" -dialect SQLITE

# Check admin-1 (subdivisions of another country)
ogrinfo -q ne_10m_admin_1_states_provinces.shp -sql \
  "SELECT name, adm0_a3, iso_3166_2 FROM ne_10m_admin_1_states_provinces WHERE name LIKE '%YourTerritory%'" -dialect SQLITE
```

### Property Name Casing

ogr2ogr preserves Natural Earth's original uppercase field names: `ADM0_A3`, `ISO_A2`, `NAME`, `SOVEREIGNT`, etc. The only lowercase property is `code`, which is added by the SQL expressions during filtering.

**When writing jq filters against ogr2ogr output, use the uppercase property names.** A filter on `.properties.adm0_a3` (lowercase) will silently match nothing — jq won't error, it just returns null, and your `select()` excludes everything or includes everything depending on the logic.

This exact bug caused all 52 countries to be duplicated into the subdivisions layer, overlaying the real subdivisions and making them unclickable.

### Tippecanoe GeoJSON Warnings

Tippecanoe will emit warnings like:

```
countries.geojson:5: Found ] at top level
countries.geojson:17: Reached EOF without all containers being closed
```

**These are benign.** They come from tippecanoe's streaming GeoJSON parser encountering the `crs` member that ogr2ogr includes in its output. All features are still read correctly. Verify by checking the feature count in the "N features, ... bytes" summary line.

### Tippecanoe `--read-parallel` and Multi-Line GeoJSON

`--read-parallel` makes tippecanoe split input files at newline boundaries for parallel parsing. This is safe for:
- Newline-delimited GeoJSON (one feature per line)
- GeoJSON where features fit on single lines

It **silently corrupts** pretty-printed GeoJSON where features span multiple lines — large coordinate arrays get split mid-feature, and tippecanoe silently drops the truncated features. The non_subdivided.geojson uses `jq -c` (compact output) to avoid this. If you add new jq-generated inputs, always use `-c`.

### Tippecanoe Feature Dropping

Never use `--coalesce-densest-as-needed` — it merges large subdivision features (e.g., Brazilian states) into single country-level polygons at lower zoom levels, making them unclickable. Use `--no-feature-limit --no-tile-size-limit` instead.

Similarly, avoid explicit `--simplification=N` with high values. At aggressive simplification levels, polygon geometries for smaller subdivisions can degenerate to zero-area shapes that MapLibre won't render as fills, creating invisible gaps that don't respond to clicks. The default zoom-dependent simplification is sufficient.

### MapLibre Shift+Click

MapLibre's built-in `BoxZoomHandler` intercepts `shift+mousedown` for box-zoom. The range map disables this with `boxZoom: false` in the Map constructor so shift+click can be used for country-level toggle.

### Browser Caching

After rebuilding tiles, browsers cache the old PMTiles aggressively. Always hard refresh (Cmd+Shift+R / Ctrl+Shift+R) after a rebuild. If tiles still look wrong, clear the browser cache entirely.

### Feature Verification

Use the diagnostic scripts (see "Diagnostic Scripts" section above):

```bash
# Full coverage check against DB
python3 verify_tiles.py

# Check a specific place
python3 inspect_tile.py PR

# Find where a territory lives in Natural Earth
python3 inspect_natural_earth.py GUF
```

For manual tile inspection, use `tippecanoe-decode`:

```bash
tippecanoe-decode boundaries.pmtiles Z X Y          # all layers
tippecanoe-decode -l countries boundaries.pmtiles Z X Y   # single layer
```

Tile coordinates (Z/X/Y) can be found using online tools or calculated from lat/lng at a given zoom level.

## Relationship to Places Database

The PMTiles and the `place` database table are populated from the same Natural Earth source but through independent pipelines:

- **Tiles**: `build_boundaries.sh` → `boundaries.pmtiles` (geometry for rendering)
- **Database**: `extract_places.sh` → `global_places.json` → Ecto migration (names, codes, hierarchy for queries)

The `code` property is the join key between them. Both pipelines now process all countries globally (except Antarctica), so coverage should be automatically synchronized. If you add a new territory or subdivision:

1. Verify it's extracted correctly in `build_boundaries.sh` (check for special cases like map subunits)
2. Ensure it appears in `global_places.json` via `extract_places.sh`
3. Add the migration to populate the database `place` table
