#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# build_boundaries.sh — one-shot generator for global admin boundaries
#                       vector tiles (countries + states/provinces)
#
# Usage:  ./build_boundaries.sh [OUTPUT_PMTILES]
#         ./build_boundaries.sh boundaries.pmtiles
#
# Requirements (all OSS-licensed):
#   * curl / wget           — file download
#   * unzip                 — extract Natural Earth zips
#   * ogr2ogr / ogrinfo     — GDAL >= 3.0 (MIT)
#   * tippecanoe            — Felt Tippecanoe (BSD)
#
# The script downloads Natural Earth Admin-0 & Admin-1 shapefiles, includes
# all countries and territories globally (excluding Antarctica), adds a stable
# "code" property (ISO-3166-1 alpha-2 for countries, ISO-3166-2 for states),
# and outputs two named layers in a single PMTiles file:
#   * countries     — Admin-0 polygons with ISO alpha-2 `code` property
#   * subdivisions  — Admin-1 polygons with ISO 3166-2 `code` property
# -----------------------------------------------------------------------------
set -euo pipefail

# -------- Tool Check ----------------------------------------------------------
function check_tool() {
    local tool=$1
    local install_hint=$2
    if ! command -v "$tool" &> /dev/null; then
        echo "Error: Required tool '$tool' is not installed." >&2
        echo "Installation hint: $install_hint" >&2
        exit 1
    fi
}

# Check for required tools
echo "==> Checking for required tools..." >&2
check_tool "curl" "brew install curl"
check_tool "unzip" "brew install unzip"
check_tool "ogr2ogr" "brew install gdal"
check_tool "ogrinfo" "brew install gdal"
check_tool "tippecanoe" "brew install tippecanoe"

# -------- Parameters ----------------------------------------------------------
OUT_PM=${1:-"boundaries.pmtiles"}
TMP=$(mktemp -d)
SRC_DIR=$TMP/src
TRIM_DIR=$TMP/trim
CACHE_DIR="${HOME}/.cache/naturalearth"
CACHE_CULTURAL="${CACHE_DIR}/10m_cultural.zip"
CACHE_PHYSICAL="${CACHE_DIR}/10m_physical.zip"
# Using AWS Open Data Program mirror
CULTURAL_URL="https://naturalearth.s3.amazonaws.com/10m_cultural/10m_cultural.zip"
PHYSICAL_URL="https://naturalearth.s3.amazonaws.com/10m_physical/10m_physical.zip"

# Territories in NE map_subunits (not in admin_0_countries).
# SU_A3 code -> desired ISO alpha-2 code for our tiles.
# Parallel arrays because macOS bash 3.2 lacks associative arrays.
SUBUNIT_SU_A3=( "GUF" "GLP" "MTQ" "REU" "MYT" "NLY" "CXR" "CCK" "TKL" "NSV" "BVT" )
SUBUNIT_ALPHA2=("GF"  "GP"  "MQ"  "RE"  "YT"  "BQ"  "CX"  "CC"  "TK"  "SJ"  "BV"  )

mkdir -p "$SRC_DIR" "$TRIM_DIR" "$CACHE_DIR"

# -------- Helpers -------------------------------------------------------------
function grab() {
  local url=$1 dest=$2
  echo "==> Downloading $(basename "$url")..." >&2

  # Try downloading with curl, with retries and proper error handling
  if ! curl -L --fail --retry 3 --retry-delay 5 "$url" -o "$dest"; then
    echo "Error: Failed to download $(basename "$url")" >&2
    echo "Please check your internet connection and try again." >&2
    echo "If the issue persists, you can manually download the file from:" >&2
    echo "https://www.naturalearthdata.com/downloads/10m-cultural-vectors/" >&2
    echo "and place it at: $dest" >&2
    exit 1
  fi

  # Verify the file is a valid zip
  if ! unzip -t "$dest" > /dev/null 2>&1; then
    echo "Error: Downloaded file $(basename "$dest") is corrupted" >&2
    echo "Please try running the script again." >&2
    rm -f "$dest"
    exit 1
  fi
}

function extract_zip() {
  local zip=$1 dest=$2
  if ! unzip -q -o -d "$dest" "$zip"; then
    echo "Error: Failed to extract $(basename "$zip")" >&2
    exit 1
  fi
}

# -------- 1. Fetch Natural Earth shapefiles ----------------------------------
echo "==> Fetching Natural Earth Admin layers" >&2

# Check if we have cached versions
for url in "$CULTURAL_URL" "$PHYSICAL_URL"; do
  cache_file="${CACHE_DIR}/$(basename "$url")"
  if [ -f "$cache_file" ]; then
    echo "    Using cached Natural Earth data from $cache_file" >&2
    # Verify the cached file is still valid
    if ! unzip -t "$cache_file" > /dev/null 2>&1; then
      echo "    Cached file is corrupted, downloading fresh copy..." >&2
      grab "$url" "$cache_file"
    fi
  else
    echo "    No cached version found, downloading fresh copy..." >&2
    grab "$url" "$cache_file"
  fi
done

# Extract only the files we need
echo "==> Extracting required shapefiles..." >&2
extract_zip "$CACHE_CULTURAL" "$SRC_DIR"
extract_zip "$CACHE_PHYSICAL" "$SRC_DIR"

# -------- 2. Process shapefiles ---------------------------------------------
echo "==> Processing shapefiles..." >&2

# Find the specific shapefiles we need
ADM0_SHAPE=$(find "$SRC_DIR" -name "ne_10m_admin_0_countries.shp" -print -quit)
ADM1_SHAPE=$(find "$SRC_DIR" -name "ne_10m_admin_1_states_provinces.shp" -print -quit)
LAKES_SHAPE=$(find "$SRC_DIR" -name "ne_10m_lakes.shp" -print -quit)
SUBUNITS_SHAPE=$(find "$SRC_DIR" -name "ne_10m_admin_0_map_subunits.shp" -print -quit)

# Verify we found the required shapefiles
if [ -z "$ADM0_SHAPE" ] || [ -z "$ADM1_SHAPE" ] || [ -z "$LAKES_SHAPE" ] || [ -z "$SUBUNITS_SHAPE" ]; then
  echo "Error: Could not find required shapefiles in $SRC_DIR" >&2
  echo "Please check if the zip files were extracted correctly." >&2
  exit 1
fi

ADM0_LAYER=$(basename "${ADM0_SHAPE%.shp}")
ADM1_LAYER=$(basename "${ADM1_SHAPE%.shp}")
SUBUNITS_LAYER=$(basename "${SUBUNITS_SHAPE%.shp}")

# Derive STATE_COUNTRIES dynamically: countries with >3 admin-1 subdivisions
echo "Determining countries with subdivisions..." >&2
STATE_COUNTRIES=()
while IFS=, read -r a3code cnt; do
  [ "$a3code" = "adm0_a3" ] && continue  # skip header
  [ -z "$a3code" ] && continue
  STATE_COUNTRIES+=("$a3code")
done < <(ogr2ogr -f CSV /vsistdout/ "$ADM1_SHAPE" \
  -sql "SELECT adm0_a3, COUNT(*) as cnt FROM \"$ADM1_LAYER\" WHERE adm0_a3 != '-99' GROUP BY adm0_a3 HAVING cnt > 3" \
  -dialect SQLITE 2>/dev/null)
echo "    Found ${#STATE_COUNTRIES[@]} countries with subdivisions" >&2

# Create a temporary shapefile with all countries except Antarctica (used for lake clipping)
echo "Creating temporary country boundaries..." >&2
if ! ogr2ogr -f "ESRI Shapefile" \
    -lco ENCODING=UTF-8 \
    "$TRIM_DIR/countries_temp.shp" "$ADM0_SHAPE" \
    -sql "SELECT * FROM \"$ADM0_LAYER\" WHERE adm0_a3 != 'ATA'" \
    -dialect SQLITE 2>/dev/null; then
  echo "Error: Failed to create temporary country boundaries" >&2
  exit 1
fi

# Process countries and territories with stable ISO alpha-2 code property
# ISO_A2 can be '-99' for some territories, so fall back to first 2 chars of ADM0_A3
echo "Processing countries and territories..." >&2
if ! ogr2ogr -f "ESRI Shapefile" \
    -lco ENCODING=UTF-8 \
    "$TRIM_DIR/ne_10m_admin_0_countries.shp" "$ADM0_SHAPE" \
    -sql "SELECT *, CASE WHEN ISO_A2 IS NOT NULL AND ISO_A2 != '-99' THEN ISO_A2 ELSE SUBSTR(adm0_a3, 1, 2) END AS code FROM \"$ADM0_LAYER\" WHERE adm0_a3 != 'ATA'" \
    -dialect SQLITE 2>/dev/null; then
  echo "Error: Failed to process countries" >&2
  exit 1
fi

# -------- 2b. Extract territories from map_subunits --------------------------
# Some territories (French overseas departments, Caribbean Netherlands, Christmas
# Island, etc.) are geo-units in Natural Earth — they appear in map_subunits with
# SU_A3 codes, not in admin_0_countries. We extract each one with its correct ISO
# alpha-2 code and append to the countries shapefile.
echo "Extracting territories from map_subunits..." >&2

for i in "${!SUBUNIT_SU_A3[@]}"; do
  su_a3="${SUBUNIT_SU_A3[$i]}"
  alpha2="${SUBUNIT_ALPHA2[$i]}"
  echo "    $su_a3 → code=$alpha2" >&2
  if ! ogr2ogr -f "ESRI Shapefile" \
      -lco ENCODING=UTF-8 \
      -append \
      "$TRIM_DIR/ne_10m_admin_0_countries.shp" "$SUBUNITS_SHAPE" \
      -sql "SELECT *, '$alpha2' AS code FROM \"$SUBUNITS_LAYER\" WHERE SU_A3 = '$su_a3'" \
      -dialect SQLITE 2>/dev/null; then
    echo "Error: Failed to extract $su_a3 from map_subunits" >&2
    exit 1
  fi

  # Also append to the lake-clipping boundary
  ogr2ogr -f "ESRI Shapefile" \
      -lco ENCODING=UTF-8 \
      -append \
      "$TRIM_DIR/countries_temp.shp" "$SUBUNITS_SHAPE" \
      -sql "SELECT * FROM \"$SUBUNITS_LAYER\" WHERE SU_A3 = '$su_a3'" \
      -dialect SQLITE 2>/dev/null
done

# Process states/provinces for countries with subdivisions
echo "Processing states/provinces..." >&2
STATE_CODES=$(printf "'%s'," "${STATE_COUNTRIES[@]}" | sed 's/,$//')
if ! ogr2ogr -f "ESRI Shapefile" \
    -lco ENCODING=UTF-8 \
    "$TRIM_DIR/ne_10m_admin_1_states_provinces.shp" "$ADM1_SHAPE" \
    -sql "SELECT *, COALESCE(iso_3166_2, adm1_code) AS code FROM \"$ADM1_LAYER\" WHERE adm0_a3 IN ($STATE_CODES)" \
    -dialect SQLITE 2>/dev/null; then
  echo "Error: Failed to filter states/provinces" >&2
  exit 1
fi

# Process lakes (only large ones — scalerank filter only, no spatial clipping
# since we're global and large lakes are already on land)
echo "Processing lakes..." >&2
if ! ogr2ogr -f "ESRI Shapefile" \
    -lco ENCODING=UTF-8 \
    "$TRIM_DIR/ne_10m_lakes.shp" "$LAKES_SHAPE" \
    -sql "SELECT * FROM \"$(basename "${LAKES_SHAPE%.shp}")\" WHERE scalerank < 2" \
    -dialect SQLITE 2>/dev/null; then
  echo "Error: Failed to filter lakes by scalerank" >&2
  exit 1
fi

# Clean up temporary files
rm -f "$TRIM_DIR/countries_temp."*

# -------- 3. Convert shapefiles to GeoJSON -----------------------------------
echo "==> Converting shapefiles to GeoJSON..." >&2

GEOJSON_DIR="$TMP/geojson"
mkdir -p "$GEOJSON_DIR"

for shp in "$TRIM_DIR"/*.shp; do
  base=$(basename "$shp" .shp)
  final_json="$GEOJSON_DIR/$base.geojson"

  # Convert to GeoJSON (ogr2ogr handles encoding via -lco ENCODING)
  if ! ogr2ogr -f GeoJSON \
       -preserve_fid \
       -lco ENCODING=UTF-8 \
       "$final_json" \
       "$shp" 2>/dev/null; then
    echo "Error: Failed to convert $base to GeoJSON" >&2
    exit 1
  fi
done

# Verify expected GeoJSON files exist
COUNTRIES_GEOJSON="$GEOJSON_DIR/ne_10m_admin_0_countries.geojson"
SUBDIVISIONS_GEOJSON="$GEOJSON_DIR/ne_10m_admin_1_states_provinces.geojson"
LAKES_GEOJSON="$GEOJSON_DIR/ne_10m_lakes.geojson"

if [ ! -f "$COUNTRIES_GEOJSON" ] || [ ! -f "$SUBDIVISIONS_GEOJSON" ]; then
  echo "Error: Expected GeoJSON files not found in $GEOJSON_DIR" >&2
  exit 1
fi

# -------- 3b. Merge non-subdivided countries into subdivisions ----------------
# Countries/territories without admin-1 subdivisions (small islands, territories)
# need to appear in the subdivisions layer so they're clickable on the map.
# We extract their country polygons and add them with subdivision-compatible
# properties: code (ISO alpha-2), name, iso_a2 (same as code for these).
echo "==> Merging non-subdivided countries into subdivisions layer..." >&2

# Build the list of STATE_COUNTRIES alpha-3 codes for jq filtering
STATE_CODES_JSON=$(printf '"%s",' "${STATE_COUNTRIES[@]}" | sed 's/,$//')

# Extract non-subdivided country features as a standalone GeoJSON file.
# Rather than merging into the large subdivisions GeoJSON (which corrupts
# under jq with large files), we pass this as a second input to tippecanoe
# with the same layer name — tippecanoe merges them automatically.
#
# IMPORTANT: Output as newline-delimited GeoJSON (one feature per line via
# jq -c) because tippecanoe's --read-parallel splits input at newline
# boundaries. Pretty-printed multi-line GeoJSON causes features with large
# coordinate arrays (Greenland, French Guiana, etc.) to be silently
# truncated, dropping them from the output tiles.
NON_SUBDIV_GEOJSON="$GEOJSON_DIR/non_subdivided.geojson"
jq -c --argjson subdivided "[$STATE_CODES_JSON]" '{
  type: "FeatureCollection",
  features: [
    .features[]
    | select(.properties.ADM0_A3 as $a3 | $subdivided | index($a3) | not)
    | {
        type: .type,
        geometry: .geometry,
        properties: {
          code: .properties.code,
          name: .properties.NAME,
          iso_a2: .properties.code
        }
      }
  ]
}' "$COUNTRIES_GEOJSON" > "$NON_SUBDIV_GEOJSON"

NON_SUBDIV_COUNT=$(jq '.features | length' "$NON_SUBDIV_GEOJSON")
echo "    Adding $NON_SUBDIV_COUNT non-subdivided countries/territories" >&2

# -------- 4. Encode vector tiles with Tippecanoe -----------------------------
echo "==> Encoding vector tiles ($OUT_PM)..." >&2

# Build tippecanoe args — lakes are optional (may not exist if clipping found none)
LAKES_ARG=""
if [ -f "$LAKES_GEOJSON" ]; then
  LAKES_ARG="--named-layer=lakes:$LAKES_GEOJSON"
fi

if ! tippecanoe -o "$OUT_PM" \
    --named-layer=countries:"$COUNTRIES_GEOJSON" \
    --named-layer=subdivisions:"$SUBDIVISIONS_GEOJSON" \
    --named-layer=subdivisions:"$NON_SUBDIV_GEOJSON" \
    $LAKES_ARG \
    --force \
    --minimum-zoom=1 \
    --maximum-zoom=10 \
    --no-feature-limit \
    --no-tile-size-limit \
    --detect-shared-borders \
    --read-parallel; then
  echo "Error: Failed to create vector tiles" >&2
  exit 1
fi

echo "" >&2
echo "Finished: $OUT_PM" >&2
