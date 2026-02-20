#!/usr/bin/env python3
"""
inspect_natural_earth.py — Find where a territory appears in Natural Earth layers.

Given an ISO alpha-3 code, searches admin_0_countries, admin_0_map_subunits,
and admin_1_states_provinces to show where the territory lives. Useful when
adding new territories to build_boundaries.sh.

Usage:
  python3 inspect_natural_earth.py <ISO_A3_CODE> [NE_CACHE_DIR]

Examples:
  python3 inspect_natural_earth.py KNA          # Saint Kitts and Nevis
  python3 inspect_natural_earth.py GUF          # French Guiana (in subunits)
  python3 inspect_natural_earth.py BES          # Caribbean Netherlands (in admin-1)

Requires: ogrinfo (from GDAL)
"""
import os
import subprocess
import sys
from pathlib import Path

DEFAULT_CACHE_DIR = Path.home() / ".cache" / "naturalearth"

# Layers to search, with the field names to query
LAYERS = [
    {
        "file_pattern": "ne_10m_admin_0_countries",
        "label": "Admin-0 Countries",
        "search_fields": ["ADM0_A3", "ISO_A3", "SOV_A3", "GU_A3", "SU_A3"],
        "display_fields": ["NAME", "ADM0_A3", "ISO_A2", "ISO_A3", "SOV_A3", "TYPE", "ADMIN"],
    },
    {
        "file_pattern": "ne_10m_admin_0_map_subunits",
        "label": "Admin-0 Map Subunits",
        "search_fields": ["ADM0_A3", "ISO_A3", "SOV_A3", "GU_A3", "SU_A3"],
        "display_fields": ["NAME", "ADM0_A3", "SU_A3", "ISO_A2", "TYPE", "ADMIN", "GEOUNIT"],
    },
    {
        "file_pattern": "ne_10m_admin_1_states_provinces",
        "label": "Admin-1 States/Provinces",
        "search_fields": ["adm0_a3", "iso_a2", "iso_3166_2"],
        "display_fields": ["name", "adm0_a3", "iso_a2", "iso_3166_2", "type_en", "admin"],
    },
]


def find_shapefile(cache_dir, pattern):
    """Find a shapefile matching the pattern in extracted NE data."""
    # Search in the cache dir for extracted shapefiles
    for root, dirs, files in os.walk(cache_dir):
        for f in files:
            if f == f"{pattern}.shp":
                return Path(root) / f
    # May need to extract first
    return None


def search_layer(shp_path, layer_config, search_code):
    """Search a Natural Earth layer for a code using ogrinfo."""
    layer_name = shp_path.stem
    results = []

    for field in layer_config["search_fields"]:
        # Use SQL query to search (case-insensitive)
        sql = f"SELECT * FROM \"{layer_name}\" WHERE UPPER({field}) = UPPER('{search_code}')"
        result = subprocess.run(
            ["ogrinfo", "-ro", "-geom=NO", str(shp_path), "-sql", sql, "-dialect", "SQLITE"],
            capture_output=True, text=True,
        )

        if "OGRFeature" in result.stdout:
            results.append({
                "matched_field": field,
                "output": result.stdout,
            })

    return results


def extract_if_needed(cache_dir):
    """Extract NE zip files if shapefiles aren't already extracted."""
    cultural_zip = cache_dir / "10m_cultural.zip"
    if not cultural_zip.exists():
        print(f"Error: Natural Earth data not cached at {cache_dir}", file=sys.stderr)
        print("Run build_boundaries.sh first to download the data.", file=sys.stderr)
        sys.exit(1)

    # Check if already extracted by looking for a known shapefile
    test_shp = find_shapefile(cache_dir, "ne_10m_admin_0_countries")
    if test_shp:
        return  # Already extracted

    print("Extracting Natural Earth data...")
    extract_dir = cache_dir / "extracted"
    extract_dir.mkdir(exist_ok=True)
    subprocess.run(["unzip", "-q", "-o", "-d", str(extract_dir), str(cultural_zip)], check=True)


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 inspect_natural_earth.py <ISO_A3_CODE> [NE_CACHE_DIR]", file=sys.stderr)
        sys.exit(1)

    search_code = sys.argv[1].upper()
    cache_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_CACHE_DIR

    print(f"Searching for '{search_code}' in Natural Earth 10m layers")
    print(f"Cache dir: {cache_dir}")
    print()

    extract_if_needed(cache_dir)

    found_anywhere = False

    for layer_config in LAYERS:
        shp_path = find_shapefile(cache_dir, layer_config["file_pattern"])
        if not shp_path:
            print(f"  {layer_config['label']}: shapefile not found, skipping")
            continue

        results = search_layer(shp_path, layer_config, search_code)

        if results:
            found_anywhere = True
            print(f"FOUND in {layer_config['label']}:")
            # Deduplicate results (same feature may match multiple fields)
            seen_outputs = set()
            for r in results:
                if r["output"] not in seen_outputs:
                    seen_outputs.add(r["output"])
                    print(f"  Matched on field: {r['matched_field']}")
                    # Parse and display key fields
                    for line in r["output"].split("\n"):
                        line = line.strip()
                        if not line:
                            continue
                        for field in layer_config["display_fields"]:
                            if line.startswith(f"{field} ") or line.startswith(f"{field.upper()} "):
                                print(f"    {line}")
                                break
                        if line.startswith("OGRFeature"):
                            print(f"    {line}")
            print()
        else:
            print(f"  {layer_config['label']}: not found")

    if not found_anywhere:
        print(f"\n'{search_code}' NOT FOUND in any Natural Earth 10m layer.")
        print("This territory may not exist in Natural Earth data at this resolution.")
        sys.exit(1)
    else:
        print("Done.")


if __name__ == "__main__":
    main()
