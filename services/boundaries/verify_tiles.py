#!/usr/bin/env python3
"""
verify_tiles.py — Verify PMTiles coverage against the gallformers place database.

Reports:
  - Places in DB but missing from tiles entirely
  - Non-subdivided countries missing from subdivisions layer
  - Places in tiles but NOT in the DB (unexpected extras)
  - Code mismatches between DB and tiles

Usage:
  python3 verify_tiles.py [PMTILES_PATH] [DB_PATH]

Defaults:
  PMTILES_PATH = ../../priv/static/data/boundaries.pmtiles
  DB_PATH      = ../../priv/gallformers.sqlite

Requires: tippecanoe-decode (from tippecanoe), sqlite3 (Python stdlib)
"""
import json
import os
import sqlite3
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_PMTILES = SCRIPT_DIR / "../../priv/static/data/boundaries.pmtiles"
DEFAULT_DB = SCRIPT_DIR / "../../priv/gallformers.sqlite"


def get_db_places(db_path):
    """Load all places from the database, grouped by type."""
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    countries = {}
    subdivisions = {}

    for row in cursor.execute("SELECT id, name, code, type FROM place ORDER BY code"):
        place = dict(row)
        if place["type"] == "country":
            countries[place["code"]] = place
        elif place["type"] in ("state", "province"):
            subdivisions[place["code"]] = place

    # Determine which countries have subdivisions via place_hierarchy
    subdivided_country_codes = set()
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


def scan_tiles(pmtiles_path, zoom=3):
    """Scan all tiles at the given zoom level and collect codes per layer."""
    country_codes = set()
    subdiv_codes = set()

    max_tiles = 2 ** zoom
    for x in range(max_tiles):
        for y in range(max_tiles):
            result = subprocess.run(
                ["tippecanoe-decode", str(pmtiles_path), str(zoom), str(x), str(y)],
                capture_output=True, text=True,
            )
            stdout = result.stdout.strip()
            if not stdout:
                continue
            try:
                data = json.loads(stdout)
            except json.JSONDecodeError:
                continue

            for outer in data.get("features", []):
                layer = outer.get("properties", {}).get("layer", "")
                for f in outer.get("features", []):
                    code = f.get("properties", {}).get("code", "")
                    if not code:
                        continue
                    if layer == "countries":
                        country_codes.add(code)
                    elif layer == "subdivisions":
                        subdiv_codes.add(code)

    return country_codes, subdiv_codes


def main():
    pmtiles_path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_PMTILES
    db_path = Path(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_DB

    if not pmtiles_path.exists():
        print(f"Error: PMTiles file not found: {pmtiles_path}", file=sys.stderr)
        sys.exit(1)
    if not db_path.exists():
        print(f"Error: Database not found: {db_path}", file=sys.stderr)
        sys.exit(1)

    print(f"PMTiles: {pmtiles_path}")
    print(f"Database: {db_path}")
    print()

    # Load DB data
    db_countries, db_subdivisions, subdivided_country_codes = get_db_places(db_path)
    print(f"DB countries: {len(db_countries)}")
    print(f"DB subdivisions: {len(db_subdivisions)}")
    print(f"DB countries with subdivisions: {len(subdivided_country_codes)}")
    print()

    # Scan tiles at multiple zoom levels for completeness
    print("Scanning tiles at zoom 3 (country level)...")
    tile_countries_z3, tile_subdiv_z3 = scan_tiles(pmtiles_path, zoom=3)

    print("Scanning tiles at zoom 5 (subdivision level)...")
    tile_countries_z5, tile_subdiv_z5 = scan_tiles(pmtiles_path, zoom=5)

    # Merge across zooms
    tile_country_codes = tile_countries_z3 | tile_countries_z5
    tile_subdiv_codes = tile_subdiv_z3 | tile_subdiv_z5

    print(f"\nTile country-layer codes: {len(tile_country_codes)}")
    print(f"Tile subdivision-layer codes: {len(tile_subdiv_codes)}")

    # ---- Analysis ----
    errors = 0

    # 1. Countries in DB but missing from tiles entirely
    print("\n" + "=" * 60)
    print("COUNTRIES IN DB BUT MISSING FROM TILES")
    print("=" * 60)
    missing_countries = []
    for code, place in sorted(db_countries.items()):
        if code not in tile_country_codes:
            missing_countries.append(place)
    if missing_countries:
        for p in missing_countries:
            print(f"  MISSING: {p['code']} — {p['name']}")
            errors += 1
    else:
        print("  All DB countries found in tiles. OK")

    # 2. Non-subdivided countries missing from subdivisions layer
    print("\n" + "=" * 60)
    print("NON-SUBDIVIDED COUNTRIES MISSING FROM SUBDIVISIONS LAYER")
    print("=" * 60)
    non_subdivided_missing = []
    for code, place in sorted(db_countries.items()):
        if code not in subdivided_country_codes:
            # This is a non-subdivided country — should appear in subdivisions layer
            if code not in tile_subdiv_codes:
                non_subdivided_missing.append(place)
    if non_subdivided_missing:
        for p in non_subdivided_missing:
            in_countries = "yes" if p["code"] in tile_country_codes else "NO"
            print(f"  MISSING from subdivisions: {p['code']} — {p['name']} (in countries: {in_countries})")
            errors += 1
    else:
        print("  All non-subdivided countries found in subdivisions layer. OK")

    # 3. Subdivisions in DB but missing from tiles
    print("\n" + "=" * 60)
    print("SUBDIVISIONS IN DB BUT MISSING FROM TILES")
    print("=" * 60)
    missing_subdivs = []
    for code, place in sorted(db_subdivisions.items()):
        if code not in tile_subdiv_codes:
            missing_subdivs.append(place)
    if missing_subdivs:
        # Group by country for readability
        by_country = {}
        for p in missing_subdivs:
            country_code = p["code"].split("-")[0] if "-" in p["code"] else "??"
            by_country.setdefault(country_code, []).append(p)
        for country, places in sorted(by_country.items()):
            print(f"  {country}: {len(places)} missing subdivisions")
            for p in places[:3]:
                print(f"    {p['code']} — {p['name']}")
            if len(places) > 3:
                print(f"    ... and {len(places) - 3} more")
            errors += len(places)
    else:
        print("  All DB subdivisions found in tiles. OK")

    # 4. Codes in tiles but NOT in DB
    print("\n" + "=" * 60)
    print("CODES IN TILES BUT NOT IN DB (unexpected)")
    print("=" * 60)
    all_db_codes = set(db_countries.keys()) | set(db_subdivisions.keys())
    all_tile_codes = tile_country_codes | tile_subdiv_codes
    extra_codes = sorted(all_tile_codes - all_db_codes)
    if extra_codes:
        for code in extra_codes:
            in_layer = []
            if code in tile_country_codes:
                in_layer.append("countries")
            if code in tile_subdiv_codes:
                in_layer.append("subdivisions")
            print(f"  EXTRA: {code} (in {', '.join(in_layer)})")
    else:
        print("  No unexpected codes in tiles. OK")

    # Summary
    print("\n" + "=" * 60)
    if errors == 0:
        print("RESULT: ALL CHECKS PASSED")
    else:
        print(f"RESULT: {errors} ISSUE(S) FOUND")
    print("=" * 60)
    sys.exit(1 if errors > 0 else 0)


if __name__ == "__main__":
    main()
