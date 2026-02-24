# Global Place Expansion Design

Stream 1 of the [global expansion](2026-02-23-global-expansion-design.md). Covers the place data pipeline, migration, and tile generation for worldwide coverage.

## Approach

Replace the Western Hemisphere place expansion with a single global expansion. Since the WH expansion hasn't shipped to production, we delete the old migration and build a fresh one that takes the place table from the pre-expansion state (US/CA only) to full global coverage.

## Hierarchy

Four levels, no region:

```
Continents (NA, XC, XB, XS, XE, XF, XA, XO)
  └─ Countries (~195, classified by geography)
       └─ Subdivisions (countries with >3 NE admin-1 entries)
```

The "Western Hemisphere" region record (`WH`) is removed. Continents are the top level.

### Continent codes

| Code | Name | Status |
|------|------|--------|
| `NA` | North America | Existing |
| `XC` | Central America | Existing |
| `XB` | Caribbean | Existing |
| `XS` | South America | Existing |
| `XE` | Europe | New |
| `XF` | Africa | New |
| `XA` | Asia | New |
| `XO` | Oceania | New |

X-prefix convention avoids collisions with ISO country codes. `NA` is the legacy exception (not an ISO country code, so no collision).

## Territory Classification

Territories are classified by **geography, not politics**. European parent countries exist as European countries. Their overseas territories are independent entries under their geographic continent. No parent-child link between sovereign nation and overseas territory.

Examples:
- French Guiana (`GF`) → South America (`XS`)
- Réunion (`RE`) → Africa (`XF`)
- French Polynesia (`PF`) → Oceania (`XO`)
- Hong Kong (`HK`) → Asia (`XA`)
- Greenland (`GL`) → North America (`NA`)
- Faroe Islands (`FO`) → Europe (`XE`)
- Guam (`GU`) → Oceania (`XO`)

Disputed territories follow Natural Earth defaults. Taiwan is a sovereign entity under Asia. Western Sahara is a country under Africa.

## Subdivision Threshold

Countries with **more than 3** admin-1 entries in Natural Earth get subdivisions. Countries with ≤3 are leaf nodes (no subdivisions, polygon merged into the subdivisions tile layer for click handling).

Analysis of Natural Earth data confirms all countries with ≤3 entries are microstates, small island territories, or dependent territories. No ecologically significant country is excluded. Luxembourg (3 entries) is the largest country at the threshold.

The `extract_places.sh` script determines the subdivision list automatically from the data — no manual curation needed.

## Territory Edge Cases

Natural Earth stores territories in three different layers. Every overseas/dependent territory must be checked against all three to determine the correct extraction method:

| NE Layer | Example | Extraction Pattern |
|----------|---------|-------------------|
| `admin_0_countries` | Greenland, Gibraltar, Puerto Rico | Add to `COUNTRIES` array |
| `admin_0_map_subunits` | French Guiana, Réunion, Guadeloupe | Add to `SUBUNIT` arrays with code mapping |
| `admin_1_states_provinces` | Caribbean Netherlands (BQ) | Custom extraction by admin-1 codes |

Countries with overseas territories to systematically verify:
- **France** — Réunion, Mayotte, New Caledonia, French Polynesia, Wallis & Futuna, Saint Barthélemy, Saint Martin
- **UK** — Gibraltar, St. Helena, Ascension, Tristan da Cunha, Pitcairn, British Indian Ocean Territory, South Georgia, Falklands
- **Netherlands** — Aruba, Curaçao, Sint Maarten, Caribbean Netherlands
- **US** — Puerto Rico, USVI, Guam, American Samoa, Northern Mariana Islands
- **Denmark** — Greenland, Faroe Islands
- **Australia** — Norfolk Island, Christmas Island, Cocos Islands
- **New Zealand** — Cook Islands, Niue, Tokelau
- **Norway** — Svalbard, Jan Mayen, Bouvet Island
- **China** — Hong Kong, Macau
- **Portugal** — Azores, Madeira (likely admin-1 of Portugal, included as subdivisions)
- **Spain** — Canary Islands, Ceuta, Melilla (likely admin-1 of Spain, included as subdivisions)

Use `inspect_natural_earth.py` for each during implementation.

## Data Pipeline

### `extract_places.sh` (updated)

- Remove WH-only `STATE_COUNTRIES` filter
- Extract all countries from `admin_0_countries`
- Determine subdivision list automatically: countries with >3 admin-1 entries after filtering out garbage (empty codes, null names, tilde-suffixed codes)
- Output: `global_places.json` (replaces `western_hemisphere_places.json`)

### `build_boundaries.sh` (updated)

- Remove `COUNTRIES` whitelist — include all countries
- `STATE_COUNTRIES` derived from same >3 threshold (or maintained in parallel with extract script)
- Extend `SUBUNIT_SU_A3` / `SUBUNIT_ALPHA2` arrays for all global territories found in `map_subunits`
- Add extraction blocks for any territories found only in `admin_1` (like BQ pattern)
- All existing gotchas from README still apply: property name casing, `jq -c` for tippecanoe, `--no-feature-limit`, etc.

### Migration

**Delete**: `20260219140816_add_western_hemisphere_places.exs` and `priv/repo/data/western_hemisphere_places.json`

**New migration** from pre-expansion baseline:

1. Recreate `place` table (UNIQUE on `code` instead of `name`)
2. Migrate existing US/CA codes to ISO 3166-2 format
3. Fix Saint Pierre & Miquelon type
4. Insert 8 continents (no region level)
5. Insert all ~195 countries with geographic continent assignments
6. Insert all subdivisions from `global_places.json`
7. Wire hierarchy: continents have no parent, countries → continents, subdivisions → countries

Countries and continent assignments are hardcoded in the migration. Subdivisions come from the JSON data file.

**Prerequisite**: `make download-db` to get a fresh pre-expansion database before running the new migration.

### Verification

- `verify_tiles.py` validates PMTiles coverage against the place table
- `inspect_tile.py` for spot-checking individual territories
- Place count sanity check after migration (expect ~2500-3500 total places)
- `PLACE_REFERENCE.md` regenerated for global coverage

## What Doesn't Change

- Place schema (`id`, `name`, `code`, `type`) — no columns added or removed
- `place_hierarchy` table — same structure
- All Places context functions — query hierarchy generically
- All Ranges context functions — work on place codes
- Range map JS hook — works on codes, doesn't care about geography
- `range_map` component — unchanged
- Admin pages — work on places generically
- Public pages — unchanged

## Implementation Order

1. Delete old migration and `western_hemisphere_places.json`
2. Update `extract_places.sh` for global scope → generate `global_places.json`
3. Update `build_boundaries.sh` for global scope → generate tiles
4. Run `verify_tiles.py` to validate tile coverage
5. `make download-db` for fresh pre-expansion database
6. Write new global migration reading from `global_places.json`
7. Run migration, verify place counts
8. Update `PLACE_REFERENCE.md`
