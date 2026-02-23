# Global Place Expansion — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the Western Hemisphere place expansion with a global expansion covering ~195 countries and ~2500-3500 subdivisions.

**Architecture:** Two parallel pipelines from Natural Earth data — `extract_places.sh` generates a JSON file for the Ecto migration, `build_boundaries.sh` generates PMTiles for the map. Both pipelines go from WH-only to global. The old WH migration is deleted and replaced with a fresh global migration. A fresh pre-expansion database is downloaded before running the new migration.

**Tech Stack:** Shell scripts (ogr2ogr, jq, tippecanoe), Elixir/Ecto migrations, SQLite, Python verification scripts.

---

## Task 1: Delete old WH migration and data file

**Files:**
- Delete: `priv/repo/migrations/20260219140816_add_western_hemisphere_places.exs`
- Delete: `priv/repo/data/western_hemisphere_places.json`

**Step 1: Delete the files**

```bash
rm priv/repo/migrations/20260219140816_add_western_hemisphere_places.exs
rm priv/repo/data/western_hemisphere_places.json
```

**Step 2: Download fresh pre-expansion database**

The current local DB has the WH migration applied. We need a fresh copy that only has the pre-expansion state (US/CA places).

```bash
make download-db
```

**Step 3: Verify the fresh DB has the old place data**

```bash
sqlite3 priv/gallformers.sqlite "SELECT COUNT(*) FROM place"
```

Expected: ~69 (US states + Canadian provinces + a few countries). If you see ~566, the S3 snapshot has the WH migration — this is a problem we'll need to work around.

**Step 4: Commit**

```bash
git rm priv/repo/migrations/20260219140816_add_western_hemisphere_places.exs
git rm priv/repo/data/western_hemisphere_places.json
git commit -m "Remove Western Hemisphere migration in preparation for global expansion"
```

---

## Task 2: Investigate global territory locations in Natural Earth

Before updating any scripts, systematically check where every overseas/dependent territory lives in Natural Earth. This determines which extraction pattern each needs.

**Files:**
- Read: `services/boundaries/inspect_natural_earth.py`

**Step 1: Check all French overseas territories**

```bash
cd services/boundaries
for code in GUF GLP MTQ REU MYT NCL PYF WLF BLM MAF; do
  echo "--- $code ---"
  python3 inspect_natural_earth.py "$code"
done
```

Record which layer each appears in (admin_0_countries, map_subunits, or admin_1).

**Step 2: Check UK overseas territories**

```bash
for code in GIB SHN PCN IOT; do
  echo "--- $code ---"
  python3 inspect_natural_earth.py "$code"
done
```

Note: Falklands (FLK), South Georgia (SGS), Bermuda (BMU), Cayman (CYM), etc. are already in the WH build — they're in admin_0_countries.

**Step 3: Check Dutch territories not already handled**

```bash
for code in ABW CUW SXM BES; do
  echo "--- $code ---"
  python3 inspect_natural_earth.py "$code"
done
```

BES (Caribbean Netherlands) is already known to be in admin_1 only.

**Step 4: Check US Pacific territories**

```bash
for code in GUM ASM MNP UMI; do
  echo "--- $code ---"
  python3 inspect_natural_earth.py "$code"
done
```

**Step 5: Check Danish, Australian, NZ, Norwegian, Chinese territories**

```bash
for code in FRO SJM BVT NFK CXR CCK COK NIU TKL HKG MAC; do
  echo "--- $code ---"
  python3 inspect_natural_earth.py "$code"
done
```

**Step 6: Document findings**

Create a working document listing every territory, which NE layer it's in, and what extraction pattern it needs. Group into:
- Category A: In `admin_0_countries` → add to COUNTRIES array
- Category B: In `map_subunits` → add to SUBUNIT arrays
- Category C: In `admin_1` only → add custom extraction block

This document drives the script updates in Tasks 3 and 4.

**Step 7: Commit the findings**

Commit the territory investigation document so the information is preserved.

---

## Task 3: Update `extract_places.sh` for global scope

**Files:**
- Modify: `services/boundaries/extract_places.sh`

**Step 1: Rename output and update header comments**

Change default output from `western_hemisphere_places.json` to `global_places.json`. Update the script header to reflect global scope.

**Step 2: Remove WH-only STATE_COUNTRIES filter**

Replace the hardcoded `STATE_COUNTRIES` array with dynamic detection. Query Natural Earth to find all countries with >3 admin-1 entries:

```bash
# Instead of hardcoded array, determine automatically
# Extract all iso_a2 codes with >3 admin-1 entries
ogr2ogr -f CSV /vsistdout/ "$ADM1" \
  -sql "SELECT iso_a2, COUNT(*) as cnt FROM ne_10m_admin_1_states_provinces WHERE iso_a2 != '-99' GROUP BY iso_a2 HAVING cnt > 3 ORDER BY iso_a2" \
  -dialect SQLITE 2>/dev/null
```

Parse the CSV output into the `STATE_COUNTRIES` array dynamically.

**Step 3: Handle known code fixes globally**

The existing script fixes Bogota (CO-DC) and Lima Province (PE-LMA). Check if there are similar issues for other countries by looking for duplicate codes in the output:

```bash
jq '[.[].code] | group_by(.) | map(select(length > 1)) | .[][0]' "$TMP/raw.json"
```

Fix any duplicates found.

**Step 4: Run the script and validate output**

```bash
cd services/boundaries
./extract_places.sh ../../priv/repo/data/global_places.json
```

Check the output:
- Total count should be ~2500-3500 subdivisions
- All expected countries represented
- No empty codes or names
- No duplicate codes

```bash
jq length ../../priv/repo/data/global_places.json
jq '[.[].code] | group_by(.) | map(select(length > 1))' ../../priv/repo/data/global_places.json
```

**Step 5: Commit**

```bash
git add services/boundaries/extract_places.sh priv/repo/data/global_places.json
git commit -m "Update extract_places.sh for global scope and generate global_places.json"
```

---

## Task 4: Update `build_boundaries.sh` for global scope

**Files:**
- Modify: `services/boundaries/build_boundaries.sh`

This is the most complex task. The script needs several changes.

**Step 1: Update header comments**

Replace all "Western Hemisphere" references with "global" scope.

**Step 2: Replace COUNTRIES array with all countries**

Remove the hardcoded WH-only list. Replace with all countries from Natural Earth. The simplest approach: instead of a whitelist, use a blacklist (exclude Antarctica and any other unwanted entries) or include everything.

Two approaches:
- **Option A:** Remove the WHERE filter entirely — include all countries from `admin_0_countries`. This is the simplest change.
- **Option B:** Build the full list of ~195 alpha-3 codes.

Option A is simpler and more maintainable. The ogr2ogr SQL becomes:

```sql
SELECT *, CASE WHEN ISO_A2 IS NOT NULL AND ISO_A2 != '-99' THEN ISO_A2 ELSE SUBSTR(adm0_a3, 1, 2) END AS code
FROM ne_10m_admin_0_countries
WHERE adm0_a3 != 'ATA'  -- Exclude Antarctica
```

**Step 3: Update STATE_COUNTRIES for global scope**

Same dynamic approach as `extract_places.sh` — derive from Natural Earth data, or maintain the list matching what `extract_places.sh` determined. Since the build script needs it as a bash array for the jq filter, the simplest approach is to query NE and build the array:

```bash
# Dynamically determine countries with >3 admin-1 subdivisions
STATE_COUNTRIES=()
while IFS=, read -r code cnt; do
  [ "$code" = "iso_a2" ] && continue  # skip header
  [ -z "$code" ] || [ "$code" = "-99" ] && continue
  STATE_COUNTRIES+=("$code")
done < <(ogr2ogr -f CSV /vsistdout/ "$ADM1_SHAPE" \
  -sql "SELECT iso_a2, COUNT(*) as cnt FROM \"$ADM1_LAYER\" WHERE iso_a2 != '-99' GROUP BY iso_a2 HAVING cnt > 3" \
  -dialect SQLITE 2>/dev/null)
```

Note: The build script uses alpha-3 codes for STATE_COUNTRIES (`USA` not `US`). The non-subdivided filter in jq checks `ADM0_A3` against this array. We'll need to use alpha-3 here, not alpha-2. Adjust the query to use `adm0_a3` instead of `iso_a2`, or build a mapping.

Actually, looking more carefully at the existing script: `STATE_COUNTRIES` uses alpha-3 codes because the jq filter checks `.properties.ADM0_A3`. But the ogr2ogr subdivision filter also uses them in the `WHERE adm0_a3 IN (...)` clause. So the dynamic query should output alpha-3 codes:

```bash
# Query for alpha-3 codes of countries with >3 admin-1 subdivisions
STATE_COUNTRIES=()
while IFS=, read -r a3code cnt; do
  [ "$a3code" = "adm0_a3" ] && continue
  [ -z "$a3code" ] && continue
  STATE_COUNTRIES+=("$a3code")
done < <(ogr2ogr -f CSV /vsistdout/ "$ADM1_SHAPE" \
  -sql "SELECT adm0_a3, COUNT(*) as cnt FROM \"$ADM1_LAYER\" WHERE adm0_a3 != '-99' GROUP BY adm0_a3 HAVING cnt > 3" \
  -dialect SQLITE 2>/dev/null)
```

**Step 4: Extend SUBUNIT arrays for global territories**

Using the findings from Task 2, add all territories found in `map_subunits` to the `SUBUNIT_SU_A3` and `SUBUNIT_ALPHA2` arrays. Example additions:

```bash
SUBUNIT_SU_A3=( "GUF" "GLP" "MTQ" "REU" "MYT" "NCL" "PYF" "WLF" ... )
SUBUNIT_ALPHA2=("GF"  "GP"  "MQ"  "RE"  "YT"  "NC"  "PF"  "WF"  ... )
```

The exact entries depend on Task 2 findings.

**Step 5: Add extraction blocks for admin-1-only territories**

For territories found only in admin-1 (like BQ), add extraction blocks following the existing BQ pattern. The exact territories depend on Task 2 findings.

**Step 6: Update lake filtering**

Currently lakes are clipped to the WH country boundaries. For global scope, either:
- Clip to all country boundaries (produces a large clipping geometry but works)
- Filter by scalerank only (simpler, includes African/Asian lakes too)
- Keep scalerank < 2 filter globally (reasonable — only the largest lakes)

The simplest change: keep the existing lake pipeline but with global country boundaries for clipping.

**Step 7: Remove WH geographic clipping**

There's no explicit geographic bounding box in the script (the filtering is done by the COUNTRIES array), so removing the array filter in Step 2 handles this automatically.

**Step 8: Build and verify**

```bash
cd services/boundaries
./build_boundaries.sh ../../priv/static/data/boundaries.pmtiles
```

Check tippecanoe output:
- Feature count should be much higher than ~595 (expect ~3000-5000)
- No errors about dropped features
- File size reasonable (~8-15MB)

**Step 9: Commit**

```bash
git add services/boundaries/build_boundaries.sh
git commit -m "Update build_boundaries.sh for global scope"
```

---

## Task 5: Update verify_tiles.py for global scope

**Files:**
- Modify: `services/boundaries/verify_tiles.py`

**Step 1: Remove hardcoded STATE_COUNTRIES**

The verify script has a hardcoded `STATE_COUNTRIES_A3` set and `A3_TO_A2` mapping (lines 32-47). These are used to determine which countries are non-subdivided (should appear in the subdivisions tile layer).

Replace with a dynamic approach: query the DB for countries that have subdivisions (children in `place_hierarchy` with type state/province) vs. leaf countries.

```python
def get_db_places(db_path):
    """Load all places from the database, grouped by type."""
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    countries = {}
    subdivisions = {}
    subdivided_country_codes = set()

    for row in cursor.execute("SELECT id, name, code, type FROM place ORDER BY code"):
        place = dict(row)
        if place["type"] == "country":
            countries[place["code"]] = place
        elif place["type"] in ("state", "province"):
            subdivisions[place["code"]] = place

    # Determine which countries have subdivisions
    for row in cursor.execute("""
        SELECT DISTINCT c.code
        FROM place c
        JOIN place_hierarchy ph ON ph.parent_id = c.id
        JOIN place s ON s.id = ph.place_id AND s.type IN ('state', 'province')
        WHERE c.type = 'country'
    """):
        subdivided_country_codes.add(row["code"])

    conn.close()
    return countries, subdivisions, subdivided_country_codes
```

Update the non-subdivided check to use `subdivided_country_codes` instead of `STATE_COUNTRIES_A2`.

**Step 2: Increase scan zoom levels**

At global scale, zoom 3 may miss small territories. Consider scanning at zoom 4 as well, or increasing to zoom 4 and 6 (instead of 3 and 5). This will be slower but more thorough.

Note: Scanning at zoom 5 means 32x32 = 1024 tiles. Zoom 6 would be 4096 tiles. Keep zoom 5 as the max to avoid excessive scan time.

**Step 3: Run verification**

```bash
cd services/boundaries
python3 verify_tiles.py
```

All checks should pass. If there are failures, investigate and fix the build script or migration.

**Step 4: Commit**

```bash
git add services/boundaries/verify_tiles.py
git commit -m "Update verify_tiles.py to derive subdivided countries from DB"
```

---

## Task 6: Write the global place migration

**Files:**
- Create: `priv/repo/migrations/<timestamp>_add_global_places.exs`
- Read: `priv/repo/data/global_places.json`

**Step 1: Generate the migration file**

```bash
mix ecto.gen.migration add_global_places
```

**Step 2: Write the migration**

The migration follows the same structure as the deleted WH migration but with global scope:

1. Recreate `place` table (UNIQUE on `code` instead of `name`)
2. Migrate existing US/CA codes to ISO 3166-2 format
3. Fix Saint Pierre & Miquelon type (province → country)
4. Insert 8 continents (NA, XC, XB, XS, XE, XF, XA, XO) — no region level, no "Western Hemisphere"
5. Insert all ~195 countries with geographic continent assignments
6. Insert all subdivisions from `global_places.json`
7. Wire hierarchy: continents (no parent), countries → continents, subdivisions → countries

Key differences from the old migration:
- No "Western Hemisphere" region
- 8 continents instead of 4
- ~195 countries instead of ~50
- ~2500-3500 subdivisions instead of ~440
- Territory-to-continent assignments follow geographic classification

The country list with continent assignments must be hardcoded in the migration. Group countries by continent in module attributes:

```elixir
@europe_countries [
  {"Albania", "AL"}, {"Andorra", "AD"}, {"Austria", "AT"}, ...
]
@africa_countries [
  {"Algeria", "DZ"}, {"Angola", "AO"}, ...
]
@asia_countries [
  {"Afghanistan", "AF"}, {"Armenia", "AM"}, ...
]
@oceania_countries [
  {"Australia", "AU"}, {"Fiji", "FJ"}, ...
]
```

Overseas territories go under their geographic continent:
- `{"Réunion", "RE"}` in `@africa_countries`
- `{"French Polynesia", "PF"}` in `@oceania_countries`
- `{"Hong Kong", "HK"}` in `@asia_countries`
- `{"Faroe Islands", "FO"}` in `@europe_countries`

**Step 3: Run the migration**

```bash
mix ecto.migrate
```

**Step 4: Verify place counts**

```bash
sqlite3 priv/gallformers.sqlite "SELECT type, COUNT(*) FROM place GROUP BY type ORDER BY type"
```

Expected output approximately:
```
continent|8
country|195
province|XXXX
state|131
```

(Exact subdivision counts depend on Natural Earth data.)

Also verify hierarchy:
```bash
sqlite3 priv/gallformers.sqlite "SELECT COUNT(*) FROM place_hierarchy"
```

Should be roughly: 8 (continent→nothing, but they have no parent) + ~195 (country→continent) + ~2500-3500 (subdivision→country) = ~2700-3700 hierarchy links.

Actually continents have no parent links, so: ~195 + ~2500-3500 = ~2700-3700.

**Step 5: Verify no orphans**

```bash
sqlite3 priv/gallformers.sqlite "
  SELECT p.code, p.name, p.type
  FROM place p
  WHERE p.type IN ('state', 'province')
  AND NOT EXISTS (SELECT 1 FROM place_hierarchy ph WHERE ph.place_id = p.id)
"
```

Should return no rows (all subdivisions have a parent).

```bash
sqlite3 priv/gallformers.sqlite "
  SELECT p.code, p.name, p.type
  FROM place p
  WHERE p.type = 'country'
  AND NOT EXISTS (SELECT 1 FROM place_hierarchy ph WHERE ph.place_id = p.id)
"
```

Should return no rows (all countries have a continent parent).

**Step 6: Commit**

```bash
git add priv/repo/migrations/*_add_global_places.exs
git commit -m "Add global place expansion migration

Expands place table from ~69 US/CA entries to ~3000+ global places.
Covers 8 continents, ~195 countries, and subdivisions for all
countries with >3 admin-1 entries in Natural Earth."
```

---

## Task 7: Update PLACE_REFERENCE.md and README

**Files:**
- Modify: `services/boundaries/PLACE_REFERENCE.md`
- Modify: `services/boundaries/README.md`

**Step 1: Regenerate PLACE_REFERENCE.md**

Update to reflect global coverage. The format should match the existing structure but with all continents and countries. This can be partially automated by querying the DB:

```bash
sqlite3 priv/gallformers.sqlite "
  SELECT c.code, c.name,
    CASE WHEN EXISTS (
      SELECT 1 FROM place_hierarchy ph
      JOIN place s ON s.id = ph.place_id AND s.type IN ('state','province')
      WHERE ph.parent_id = c.id
    ) THEN 'yes' ELSE 'no' END as subdivided,
    cont.name as continent
  FROM place c
  JOIN place_hierarchy ch ON ch.place_id = c.id
  JOIN place cont ON cont.id = ch.parent_id AND cont.type = 'continent'
  WHERE c.type = 'country'
  ORDER BY cont.name, c.name
"
```

**Step 2: Update README.md**

- Replace "Western Hemisphere" references with "global"
- Update expected feature counts
- Update the `COUNTRIES` and `STATE_COUNTRIES` descriptions to reflect dynamic derivation
- Update the pipeline overview diagram

**Step 3: Commit**

```bash
git add services/boundaries/PLACE_REFERENCE.md services/boundaries/README.md
git commit -m "Update boundary pipeline docs for global scope"
```

---

## Task 8: Run full verification pipeline

**Step 1: Rebuild tiles against the migrated database**

```bash
cd services/boundaries
./build_boundaries.sh ../../priv/static/data/boundaries.pmtiles
```

**Step 2: Run tile verification**

```bash
python3 verify_tiles.py
```

All checks should pass.

**Step 3: Start the dev server and visually verify**

```bash
mix phx.server
```

- Visit a gall page with a range map — should show the full world
- Visit the admin gall-host page — map should show the full world, clicking should work
- Check that existing US/CA species still show correct ranges
- Hard refresh browser (Cmd+Shift+R) to clear cached tiles

**Step 4: Run existing tests**

```bash
mix test
```

All existing tests should pass. The test database gets rebuilt from `structure.sql` + `test_seeds.sql`, which won't include the new places. Tests that reference specific place codes (US-CA, etc.) should still work since those codes haven't changed.

**Step 5: Commit tiles if changed**

The PMTiles file is tracked in git. If it changed:

```bash
git add priv/static/data/boundaries.pmtiles
git commit -m "Rebuild boundary tiles for global coverage"
```

---

## Task 9: Update test seeds for global coverage

**Files:**
- Modify: `priv/repo/test_seeds.sql`

**Step 1: Check what place data test seeds currently have**

The test seeds likely have minimal place data. Check if they need updating for tests that reference continents or non-WH places.

**Step 2: Add representative global test data**

Add a few places per continent so tests can exercise continent-scoped queries:
- At least 1 European country + subdivision
- At least 1 African country
- At least 1 Asian country + subdivision
- At least 1 Oceanian country

Keep it minimal — just enough for tests, not the full global dataset.

**Step 3: Run tests**

```bash
make test
```

**Step 4: Commit**

```bash
git add priv/repo/test_seeds.sql
git commit -m "Add representative global places to test seeds"
```

---

## Summary of commits

1. Remove Western Hemisphere migration
2. Territory investigation document
3. Update extract_places.sh + generate global_places.json
4. Update build_boundaries.sh for global scope
5. Update verify_tiles.py
6. Global place migration
7. Update docs (PLACE_REFERENCE.md, README.md)
8. Rebuild boundary tiles
9. Update test seeds
