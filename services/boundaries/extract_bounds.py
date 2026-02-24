#!/usr/bin/env python3
"""Extract bounding boxes per place code from PMTiles.

Scans the countries and subdivisions layers at zoom levels 1-5 to find
all features, computing a bounding box for each unique `code` property.

Handles the antimeridian: tippecanoe-decode emits coordinates beyond ±180°
for features that cross the dateline (e.g., Fiji at 181°, Russia at -183°).
We normalize all longitudes to [-180, 180] and detect antimeridian-crossing
features by checking if a code has coordinates on both sides of ±170°.

Usage:
    python3 extract_bounds.py [PMTILES_PATH] [OUTPUT_JSON]
    python3 extract_bounds.py  # defaults: ../../priv/static/data/boundaries.pmtiles → ../../priv/repo/data/place_bounds.json
"""

import json
import subprocess
import sys
from collections import defaultdict


def decode_tile(pmtiles_path, z, x, y):
    """Decode a single tile, returning parsed JSON or None."""
    try:
        r = subprocess.run(
            ["tippecanoe-decode", pmtiles_path, str(z), str(x), str(y)],
            capture_output=True, text=True, timeout=30
        )
        if r.returncode != 0:
            return None
        return json.loads(r.stdout)
    except (subprocess.TimeoutExpired, json.JSONDecodeError):
        return None


def extract_coords(geometry):
    """Extract all [lng, lat] coordinate pairs from a GeoJSON geometry."""
    coords = []
    gtype = geometry.get("type", "")
    if gtype == "Polygon":
        for ring in geometry.get("coordinates", []):
            coords.extend(ring)
    elif gtype == "MultiPolygon":
        for polygon in geometry.get("coordinates", []):
            for ring in polygon:
                coords.extend(ring)
    elif gtype == "Point":
        coords.append(geometry.get("coordinates", []))
    elif gtype == "MultiPoint":
        coords.extend(geometry.get("coordinates", []))
    elif gtype == "LineString":
        coords.extend(geometry.get("coordinates", []))
    elif gtype == "MultiLineString":
        for line in geometry.get("coordinates", []):
            coords.extend(line)
    return coords


def normalize_lng(lng):
    """Normalize longitude to [-180, 180]."""
    while lng > 180:
        lng -= 360
    while lng < -180:
        lng += 360
    return lng


def compute_bbox(lngs, lats):
    """Compute bounding box, handling antimeridian-crossing features.

    For features that cross the antimeridian (have coordinates on both
    sides of ±170°), we compute the bbox that wraps around the dateline
    rather than spanning the entire globe.
    """
    if not lngs:
        return None

    south = min(lats)
    north = max(lats)

    # Check if this feature crosses the antimeridian:
    # has points both east of 170° and west of -170°
    has_far_east = any(lng > 160 for lng in lngs)
    has_far_west = any(lng < -160 for lng in lngs)
    crosses_antimeridian = has_far_east and has_far_west

    if not crosses_antimeridian:
        return [min(lngs), south, max(lngs), north]

    # For antimeridian crossings, split into east and west groups
    # and compute the bbox that wraps around 180°
    east_lngs = [lng for lng in lngs if lng >= 0]
    west_lngs = [lng for lng in lngs if lng < 0]

    if east_lngs and west_lngs:
        # West bound is the easternmost positive longitude
        # East bound is the westernmost negative longitude
        # This gives us the bbox that wraps around 180°
        west = min(east_lngs)
        east = max(west_lngs)
        return [west, south, east, north]

    return [min(lngs), south, max(lngs), north]


def main():
    pmtiles = sys.argv[1] if len(sys.argv) > 1 else "../../priv/static/data/boundaries.pmtiles"
    output = sys.argv[2] if len(sys.argv) > 2 else "../../priv/repo/data/place_bounds.json"

    # Collect all normalized longitudes and latitudes per code
    code_lngs = defaultdict(list)
    code_lats = defaultdict(list)

    total_tiles = 0
    for z in range(1, 6):
        n = 2 ** z
        print(f"Scanning zoom {z} ({n*n} tiles)...", file=sys.stderr)
        for x in range(n):
            for y in range(n):
                data = decode_tile(pmtiles, z, x, y)
                if data is None:
                    continue
                total_tiles += 1

                for layer in data.get("features", []):
                    layer_name = layer.get("properties", {}).get("layer", "")
                    if layer_name not in ("countries", "subdivisions"):
                        continue

                    for feat in layer.get("features", []):
                        code = feat.get("properties", {}).get("code", "")
                        if not code:
                            continue

                        coords = extract_coords(feat.get("geometry", {}))
                        for coord in coords:
                            if len(coord) < 2:
                                continue
                            lng = normalize_lng(coord[0])
                            lat = coord[1]
                            code_lngs[code].append(lng)
                            code_lats[code].append(lat)

    # Compute bboxes with antimeridian handling
    result = {}
    antimeridian_codes = []
    for code in sorted(code_lngs.keys()):
        bbox = compute_bbox(code_lngs[code], code_lats[code])
        if bbox is None:
            continue
        result[code] = [round(bbox[0], 2), round(bbox[1], 2), round(bbox[2], 2), round(bbox[3], 2)]
        if bbox[0] > bbox[2]:  # west > east means antimeridian crossing
            antimeridian_codes.append(code)

    with open(output, "w") as f:
        json.dump(result, f, indent=2)

    print(f"\nExtracted bounds for {len(result)} codes from {total_tiles} tiles", file=sys.stderr)
    if antimeridian_codes:
        print(f"Antimeridian-crossing codes ({len(antimeridian_codes)}): {', '.join(antimeridian_codes)}", file=sys.stderr)
    print(f"Output: {output}", file=sys.stderr)


if __name__ == "__main__":
    main()
