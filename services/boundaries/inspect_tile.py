#!/usr/bin/env python3
"""
inspect_tile.py — Find where a specific place code appears in the PMTiles file.

For a given place code (e.g., "GF", "US-CA"), searches across zoom levels and
reports which tiles contain it, in which layers.

Usage:
  python3 inspect_tile.py <CODE> [PMTILES_PATH]

Examples:
  python3 inspect_tile.py GF                    # French Guiana
  python3 inspect_tile.py US-CA                  # California
  python3 inspect_tile.py PR                     # Puerto Rico

Requires: tippecanoe-decode (from tippecanoe)
"""
import json
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_PMTILES = SCRIPT_DIR / "../../priv/static/data/boundaries.pmtiles"


def search_zoom(pmtiles_path, code, zoom):
    """Search all tiles at a zoom level for the given code."""
    results = []
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
                    f_code = f.get("properties", {}).get("code", "")
                    if f_code == code:
                        name = f.get("properties", {}).get("name", f.get("properties", {}).get("NAME", ""))
                        results.append({
                            "zoom": zoom,
                            "x": x,
                            "y": y,
                            "layer": layer,
                            "name": name,
                        })
    return results


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 inspect_tile.py <CODE> [PMTILES_PATH]", file=sys.stderr)
        sys.exit(1)

    code = sys.argv[1]
    pmtiles_path = Path(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_PMTILES

    if not pmtiles_path.exists():
        print(f"Error: PMTiles file not found: {pmtiles_path}", file=sys.stderr)
        sys.exit(1)

    print(f"Searching for code '{code}' in {pmtiles_path}")
    print()

    all_results = []
    # Search zoom levels 1-6 (higher zooms have too many tiles for exhaustive scan)
    for zoom in range(1, 7):
        tiles = 2 ** zoom
        sys.stdout.write(f"  Zoom {zoom} ({tiles}x{tiles} = {tiles*tiles} tiles)...")
        sys.stdout.flush()
        results = search_zoom(pmtiles_path, code, zoom)
        if results:
            print(f" FOUND in {len(results)} tile(s)")
            all_results.extend(results)
        else:
            print(" not found")

    if not all_results:
        print(f"\nCode '{code}' NOT FOUND in any tile at zoom 1-6.")
        sys.exit(1)

    # Summarize by layer
    print(f"\n{'=' * 50}")
    print(f"Summary for '{code}':")
    layers = {}
    for r in all_results:
        layers.setdefault(r["layer"], []).append(r)

    for layer, hits in sorted(layers.items()):
        zooms = sorted(set(h["zoom"] for h in hits))
        name = hits[0].get("name", "unknown")
        print(f"  Layer '{layer}': zoom {zooms[0]}-{zooms[-1]}, {len(hits)} tile(s), name='{name}'")

    print()
    print("Tile details:")
    for r in sorted(all_results, key=lambda r: (r["layer"], r["zoom"], r["x"], r["y"])):
        print(f"  z={r['zoom']} x={r['x']} y={r['y']}  layer={r['layer']}")


if __name__ == "__main__":
    main()
