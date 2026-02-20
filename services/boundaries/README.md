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
    ↓  ogr2ogr: filter to Western Hemisphere, add `code` property
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
| `services/boundaries/extract_places.sh` | Generates `western_hemisphere_places.json` for DB seeding (not tiles) |
| `priv/static/data/boundaries.pmtiles` | Output: vector tiles (~106MB on disk, served via HTTP range requests — browsers fetch only the tiles needed for the current viewport, typically a few hundred KB) |
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

Countries/territories without admin-1 subdivisions in Natural Earth (e.g., Puerto Rico, Bermuda, Greenland, Bahamas) need special handling. Their country polygons are copied into the `subdivisions` layer so the JS click handler can treat everything uniformly. The jq filter in the build script excludes countries listed in `STATE_COUNTRIES` (those that DO have subdivisions).

## Build Script Internals

### Country Lists

The script maintains two arrays:

- **`COUNTRIES`** (52 entries): All Western Hemisphere countries and territories to include. Uses ISO 3166-1 alpha-3 codes.
- **`STATE_COUNTRIES`** (26 entries): Subset of `COUNTRIES` that have meaningful admin-1 subdivisions. Countries NOT in this list get their polygons merged into the `subdivisions` layer.

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

- **581 features total** (as of Feb 2026)
  - ~52 countries
  - ~508 subdivisions (from Natural Earth Admin-1)
  - ~22 non-subdivided countries/territories (merged into subdivisions layer)
  - A small number of lakes

If the count is significantly different, something went wrong:
- **Much higher** (~608+): The non-subdivided filter isn't excluding STATE_COUNTRIES — check property casing in the jq filter
- **Much lower** (~100-200): tippecanoe is dropping features — check for `--coalesce-densest-as-needed` or other dropping flags

## Known Gotchas

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

### Tippecanoe Feature Dropping

Never use `--coalesce-densest-as-needed` — it merges large subdivision features (e.g., Brazilian states) into single country-level polygons at lower zoom levels, making them unclickable. Use `--no-feature-limit --no-tile-size-limit` instead.

Similarly, avoid explicit `--simplification=N` with high values. At aggressive simplification levels, polygon geometries for smaller subdivisions can degenerate to zero-area shapes that MapLibre won't render as fills, creating invisible gaps that don't respond to clicks. The default zoom-dependent simplification is sufficient.

### MapLibre Shift+Click

MapLibre's built-in `BoxZoomHandler` intercepts `shift+mousedown` for box-zoom. The range map disables this with `boxZoom: false` in the Map constructor so shift+click can be used for country-level toggle.

### Browser Caching

After rebuilding tiles, browsers cache the old PMTiles aggressively. Always hard refresh (Cmd+Shift+R / Ctrl+Shift+R) after a rebuild. If tiles still look wrong, clear the browser cache entirely.

### Feature Verification

To verify features exist in the built PMTiles:

```bash
# Decode a specific tile and check its contents
tippecanoe-decode boundaries.pmtiles Z X Y > tile.json

# Check with python
python3 -c "
import json
with open('tile.json') as f:
    data = json.load(f)
for feat in data['features']:
    if feat['type'] == 'FeatureCollection':
        layer = feat['properties'].get('layer', '?')
        codes = [f['properties'].get('code','') for f in feat.get('features',[])]
        print(f'{layer}: {len(codes)} features')
"
```

Tile coordinates (Z/X/Y) can be found using online tools or calculated from lat/lng at a given zoom level.

## Relationship to Places Database

The PMTiles and the `place` database table are populated from the same Natural Earth source but through independent pipelines:

- **Tiles**: `build_boundaries.sh` → `boundaries.pmtiles` (geometry for rendering)
- **Database**: `extract_places.sh` → `western_hemisphere_places.json` → Ecto migration (names, codes, hierarchy for queries)

The `code` property is the join key between them. If you add a new country or territory, it needs to be added to BOTH:

1. The `COUNTRIES` array in `build_boundaries.sh` (and `STATE_COUNTRIES` if it has subdivisions)
2. The places data in `western_hemisphere_places.json` and corresponding migration
