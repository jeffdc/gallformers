#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# extract_places.sh — extract subdivision names and ISO 3166-2 codes from
#                     Natural Earth shapefiles for the place table migration
#
# Usage:  ./extract_places.sh [OUTPUT_JSON]
#         ./extract_places.sh ../../priv/repo/data/western_hemisphere_places.json
#
# Requirements: ogr2ogr (GDAL), jq
#
# Uses the same cached Natural Earth data as build_boundaries.sh.
# Output: JSON array of {name, code, type, country} objects suitable for
#         the Ecto migration.
# -----------------------------------------------------------------------------
set -euo pipefail

OUT=${1:-"western_hemisphere_places.json"}
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

# Countries with subdivisions (matches build_boundaries.sh STATE_COUNTRIES)
STATE_COUNTRIES=(
    "US" "CA" "MX"
    "BZ" "CR" "SV" "GT" "HN" "NI" "PA"
    "CU" "DO" "HT" "JM"
    "AR" "BO" "BR" "CL" "CO" "EC" "GY" "PY" "PE" "SR" "UY" "VE"
)

CODES=$(printf "'%s'," "${STATE_COUNTRIES[@]}" | sed 's/,$//')

echo "==> Extracting subdivisions for ${#STATE_COUNTRIES[@]} countries..." >&2

# Extract to CSV, then convert to JSON with jq
# The build script uses iso_3166_2 as the code for subdivisions in the PMTiles
ogr2ogr -f CSV "$TMP/subdivisions.csv" "$ADM1" \
  -sql "SELECT name, iso_3166_2, iso_a2, type_en FROM ne_10m_admin_1_states_provinces WHERE iso_a2 IN ($CODES) ORDER BY iso_a2, name" \
  -dialect SQLITE 2>/dev/null

# Convert CSV to JSON, mapping type_en to our place types
# Natural Earth uses: State, Province, Department, Region, etc.
# We map to: state, province (our two subdivision types)
jq -R -s '
  split("\n") | .[1:] | map(select(length > 0)) |
  map(
    split(",") |
    if length >= 4 then
      {
        name: .[0],
        code: .[1],
        type: (.[3] | ascii_downcase |
          if . == "state" then "state"
          elif . == "province" then "province"
          else "province"
          end),
        country: .[2]
      }
    else empty end
  ) |
  # Filter out entries with empty/null codes or names (NE placeholder regions)
  map(select(.code != "" and .code != null and .name != "" and .name != null and (.code | test("~$") | not)))
' "$TMP/subdivisions.csv" > "$TMP/raw.json"

# Check for any names with commas (CSV parsing issue) and fix
# Natural Earth names shouldn't have commas, but let's verify
PROBLEM_COUNT=$(jq '[.[] | select(.name | test(","))] | length' "$TMP/raw.json")
if [ "$PROBLEM_COUNT" -gt 0 ]; then
  echo "Warning: $PROBLEM_COUNT entries have commas in names (CSV parse issue)" >&2
fi

# Fix known Natural Earth duplicate code issues:
# - Bogota and Cundinamarca both get CO-CUN; Bogota's ISO code is CO-DC
# - Lima (region) and Lima Province both get PE-LIM; Lima Province is PE-LMA
jq '
  map(
    if .name == "Bogota" and .code == "CO-CUN" then .code = "CO-DC"
    elif .name == "Lima Province" and .code == "PE-LIM" then .code = "PE-LMA"
    else . end
  ) | sort_by(.country, .name)
' "$TMP/raw.json" > "$OUT"

COUNT=$(jq length "$OUT")
echo "==> Wrote $COUNT subdivisions to $OUT" >&2
echo "==> Countries represented:" >&2
jq -r '[.[].country] | unique | .[]' "$OUT" | while read -r c; do
  n=$(jq "[.[] | select(.country==\"$c\")] | length" "$OUT")
  echo "    $c: $n subdivisions" >&2
done
