#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# extract_places.sh — extract subdivision names and ISO 3166-2 codes from
#                     Natural Earth shapefiles for the place table migration
#
# Usage:  ./extract_places.sh [OUTPUT_JSON]
#         ./extract_places.sh ../../priv/repo/data/global_places.json
#
# Requirements: ogr2ogr (GDAL), jq
#
# Uses the same cached Natural Earth data as build_boundaries.sh.
# Output: JSON array of {name, code, type, country} objects suitable for
#         the Ecto migration.
# -----------------------------------------------------------------------------
set -euo pipefail

OUT=${1:-"global_places.json"}
CACHE_DIR="${HOME}/.cache/naturalearth"
CACHE_CULTURAL="${CACHE_DIR}/10m_cultural.zip"
CULTURAL_URL="https://naturalearth.s3.amazonaws.com/10m_cultural/10m_cultural.zip"

# Check tools
for tool in ogr2ogr jq; do
  if ! command -v "$tool" &>/dev/null; then
    echo "Error: $tool not found. Install with: brew install ${tool}" >&2
    exit 1
  fi
done

# Ensure Natural Earth data is cached
if [ ! -f "$CACHE_CULTURAL" ]; then
  echo "==> Downloading Natural Earth cultural data..." >&2
  mkdir -p "$CACHE_DIR"
  curl -L --fail --retry 3 "$CULTURAL_URL" -o "$CACHE_CULTURAL"
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "==> Extracting shapefiles..." >&2
unzip -q -o "$CACHE_CULTURAL" -d "$TMP"

ADM1=$(find "$TMP" -name "ne_10m_admin_1_states_provinces.shp" -print -quit)
if [ -z "$ADM1" ]; then
  echo "Error: Could not find admin-1 shapefile" >&2
  exit 1
fi

# Dynamically determine countries with >3 admin-1 subdivisions
# Use iso_a2 since that's what our DB uses
echo "==> Detecting countries with subdivisions..." >&2
STATE_COUNTRIES=()
while IFS=, read -r code cnt; do
  [ "$code" = "iso_a2" ] && continue  # skip CSV header
  [ -z "$code" ] || [ "$code" = "-99" ] && continue
  STATE_COUNTRIES+=("$code")
done < <(ogr2ogr -f CSV /vsistdout/ "$ADM1" \
  -sql "SELECT iso_a2, COUNT(*) as cnt FROM ne_10m_admin_1_states_provinces WHERE iso_a2 != '-99' GROUP BY iso_a2 HAVING cnt > 3 ORDER BY iso_a2" \
  -dialect SQLITE 2>/dev/null)

CODES=$(printf "'%s'," "${STATE_COUNTRIES[@]}" | sed 's/,$//')

echo "==> Extracting subdivisions for ${#STATE_COUNTRIES[@]} countries..." >&2

# Extract to GeoJSON to avoid CSV quoting issues with commas in place names
# (e.g., "Rhondda, Cynon, Taff" in GB, "Southern Nations, Nationalities and
# Peoples" in ET). GeoJSON handles special characters natively.
# The build script uses iso_3166_2 as the code for subdivisions in the PMTiles
ogr2ogr -f GeoJSON "$TMP/subdivisions.geojson" "$ADM1" \
  -sql "SELECT name, iso_3166_2, iso_a2, type_en FROM ne_10m_admin_1_states_provinces WHERE iso_a2 IN ($CODES) ORDER BY iso_a2, name" \
  -dialect SQLITE 2>/dev/null

# Convert GeoJSON to our JSON format, mapping type_en to our place types
# Natural Earth uses: State, Province, Department, Region, etc.
# We map to: state, province (our two subdivision types)
jq '[
  .features[].properties |
  {
    name: .name,
    code: .iso_3166_2,
    type: ((.type_en // "") | ascii_downcase |
      if . == "state" then "state"
      else "province"
      end),
    country: .iso_a2
  }
] |
# Filter out entries with empty/null codes or names (NE placeholder regions)
map(select(.code != "" and .code != null and .name != "" and .name != null and (.code | test("~$") | not)))
' "$TMP/subdivisions.geojson" > "$TMP/raw.json"

# Check for duplicate codes before fixes
echo "==> Checking for duplicate codes..." >&2
DUPES=$(jq -r '[.[].code] | group_by(.) | map(select(length > 1)) | .[][0]' "$TMP/raw.json")
if [ -n "$DUPES" ]; then
  echo "    Duplicate codes found (will fix known ones):" >&2
  echo "$DUPES" | while read -r d; do
    echo "    - $d: $(jq -r --arg c "$d" '[.[] | select(.code == $c) | .name] | join(", ")' "$TMP/raw.json")" >&2
  done
fi

# Fix known Natural Earth duplicate code issues:
# - Bogota and Cundinamarca both get CO-CUN; Bogota's ISO code is CO-DC
# - Lima (region) and Lima Province both get PE-LIM; Lima Province is PE-LMA
# - Tehran and Alborz both get IR-07; Alborz's ISO code is IR-30
jq '
  map(
    if .name == "Bogota" and .code == "CO-CUN" then .code = "CO-DC"
    elif .name == "Lima Province" and .code == "PE-LIM" then .code = "PE-LMA"
    elif .name == "Alborz" and .code == "IR-07" then .code = "IR-30"
    else . end
  ) | sort_by(.country, .name)
' "$TMP/raw.json" > "$TMP/fixed.json"

# Deduplicate remaining codes. Natural Earth has sub-entities (cities within
# provinces, historical admin splits, etc.) that share ISO codes. For our place
# table we need exactly one entry per code. Strategy: keep the first entry per
# code (alphabetically by name within each country, since we sorted above).
DEDUPED_COUNT_BEFORE=$(jq length "$TMP/fixed.json")
jq '
  reduce .[] as $item ([];
    if (map(.code) | index($item.code)) == null then . + [$item]
    else . end
  )
' "$TMP/fixed.json" > "$OUT"
DEDUPED_COUNT_AFTER=$(jq length "$OUT")
DROPPED=$((DEDUPED_COUNT_BEFORE - DEDUPED_COUNT_AFTER))
if [ "$DROPPED" -gt 0 ]; then
  echo "    Deduplicated $DROPPED entries sharing codes with primary subdivisions" >&2
fi

# Verify no duplicates remain
REMAINING_DUPES=$(jq -r '[.[].code] | group_by(.) | map(select(length > 1)) | .[][0]' "$OUT")
if [ -n "$REMAINING_DUPES" ]; then
  echo "ERROR: Duplicate codes remain after deduplication:" >&2
  echo "$REMAINING_DUPES" | while read -r d; do
    echo "    - $d: $(jq -r --arg c "$d" '[.[] | select(.code == $c) | .name] | join(", ")' "$OUT")" >&2
  done
  exit 1
fi

COUNT=$(jq length "$OUT")
echo "==> Wrote $COUNT subdivisions to $OUT" >&2
echo "==> Countries represented:" >&2
jq -r '[.[].country] | unique | .[]' "$OUT" | while read -r c; do
  n=$(jq --arg c "$c" '[.[] | select(.country == $c)] | length' "$OUT")
  echo "    $c: $n subdivisions" >&2
done
