"""Compare pipeline extraction against human-curated baseline.

Usage:
    python scripts/compare_extraction.py <baseline.json> <extracted.json> [--db <dbname>]

Uses the gallformers alias_species table to resolve historical names to modern names.

Requires: psycopg (pip install psycopg[binary])
"""

import json
import sys
from pathlib import Path

import psycopg
from psycopg.rows import dict_row

DEFAULT_DB = "gallformers_dev"


def load_alias_map(dbname):
    """Build a map of normalized alias -> normalized current name."""
    conn = psycopg.connect(f"dbname={dbname}", row_factory=dict_row)
    rows = conn.execute("""
        SELECT a.name AS alias_name, s.name AS species_name
        FROM alias_species als
        JOIN alias a ON a.id = als.alias_id
        JOIN species s ON s.id = als.species_id
    """).fetchall()
    conn.close()

    alias_map = {}
    for row in rows:
        norm_alias = normalize_name(row["alias_name"])
        norm_current = normalize_name(row["species_name"])
        if norm_alias and norm_current:
            alias_map[norm_alias] = norm_current
    return alias_map


def normalize_name(name):
    """Normalize a species name for comparison."""
    if not name:
        return None
    n = name.strip().lower()
    for marker in ["(sexgen)", "(agamic)", "(sexual)", "(asexual)"]:
        n = n.replace(marker, "")
    return " ".join(n.split())


def resolve_name(name, alias_map):
    """Resolve a name through aliases. Returns the canonical name."""
    if not name:
        return None
    norm = normalize_name(name)
    return alias_map.get(norm, norm)


def extract_gall_names(records, alias_map):
    """Get dict of resolved gall name -> [original names]."""
    names = {}
    for r in records:
        original = normalize_name(r.get("gall_species", {}).get("name"))
        if original:
            resolved = resolve_name(original, alias_map)
            names.setdefault(resolved, []).append(original)
    return names


def extract_pairs(records, alias_map):
    """Get set of (resolved_gall, resolved_host) pairs."""
    pairs = set()
    for r in records:
        gall = resolve_name(r.get("gall_species", {}).get("name"), alias_map)
        host = resolve_name(r.get("host_species", {}).get("name"), alias_map)
        if gall and host:
            pairs.add((gall, host))
    return pairs


def compare_traits(baseline_records, extracted_records, alias_map):
    """Compare traits for gall species found in both sets."""

    def index_by_gall(records):
        idx = {}
        for r in records:
            name = resolve_name(r.get("gall_species", {}).get("name"), alias_map)
            if name and name not in idx:
                idx[name] = r
        return idx

    base_idx = index_by_gall(baseline_records)
    ext_idx = index_by_gall(extracted_records)

    common = sorted(set(base_idx.keys()) & set(ext_idx.keys()))
    if not common:
        print("\nNo common gall species to compare traits.")
        return

    trait_keys = [
        "shape",
        "color",
        "texture",
        "walls",
        "cells",
        "alignment",
        "plant_part",
        "form",
        "season",
    ]

    print(f"\n## Trait Comparison ({len(common)} common species)")
    print()

    total_match = 0
    total_partial = 0
    total_compared = 0
    trait_scores = {k: {"match": 0, "partial": 0, "total": 0} for k in trait_keys}

    for name in common:
        base_traits = base_idx[name].get("traits", {})
        ext_traits = ext_idx[name].get("traits", {})

        # Show which names matched
        ext_original = normalize_name(ext_idx[name].get("gall_species", {}).get("name"))
        base_original = normalize_name(base_idx[name].get("gall_species", {}).get("name"))
        name_note = ""
        if ext_original != base_original:
            name_note = f" (extracted as: {ext_original})"

        mismatches = []
        for trait in trait_keys:
            base_raw = base_traits.get(trait, {})
            ext_raw = ext_traits.get(trait, {})
            base_vals = set(base_raw.get("suggested", []) if isinstance(base_raw, dict) else [])
            ext_vals = set(ext_raw.get("suggested", []) if isinstance(ext_raw, dict) else [])

            trait_scores[trait]["total"] += 1
            total_compared += 1

            if base_vals == ext_vals:
                trait_scores[trait]["match"] += 1
                total_match += 1
            elif base_vals and ext_vals:
                overlap = base_vals & ext_vals
                if overlap:
                    trait_scores[trait]["partial"] += 1
                    total_partial += 1
                    mismatches.append(
                        f"  {trait}: baseline={sorted(base_vals)} extracted={sorted(ext_vals)} (partial match)"
                    )
                else:
                    mismatches.append(
                        f"  {trait}: baseline={sorted(base_vals)} extracted={sorted(ext_vals)}"
                    )
            elif base_vals:
                mismatches.append(f"  {trait}: baseline={sorted(base_vals)} extracted=[]")
            elif ext_vals:
                mismatches.append(f"  {trait}: baseline=[] extracted={sorted(ext_vals)}")

        # Detachable
        base_det = base_traits.get("detachable", "unknown")
        ext_det = ext_traits.get("detachable", "unknown")
        if isinstance(ext_det, dict):
            ext_det = ext_det.get("suggested", "unknown")
        total_compared += 1
        if base_det == ext_det:
            total_match += 1
        else:
            mismatches.append(f"  detachable: baseline={base_det} extracted={ext_det}")

        if mismatches:
            print(f"**{name}**{name_note}")
            for m in mismatches:
                print(m)
            print()

    if total_compared:
        exact_pct = total_match / total_compared * 100
        partial_pct = (total_match + total_partial) / total_compared * 100
        print(f"Exact match: {total_match}/{total_compared} ({exact_pct:.1f}%)")
        print(
            f"Exact + partial: {total_match + total_partial}/{total_compared} ({partial_pct:.1f}%)"
        )

    print("\nPer-trait accuracy (exact / partial / total):")
    for trait in trait_keys:
        s = trait_scores[trait]
        if s["total"]:
            print(f"  {trait}: {s['match']}+{s['partial']}/{s['total']}")


def main():
    if len(sys.argv) < 3:
        print(
            "Usage: python scripts/compare_extraction.py <baseline.json> <extracted.json> [--db <dbname>]"
        )
        sys.exit(1)

    baseline = json.loads(Path(sys.argv[1]).read_text())
    extracted = json.loads(Path(sys.argv[2]).read_text())

    dbname = DEFAULT_DB
    if "--db" in sys.argv:
        idx = sys.argv.index("--db")
        dbname = sys.argv[idx + 1]

    alias_map = {}
    try:
        alias_map = load_alias_map(dbname)
        print(f"Loaded {len(alias_map)} name aliases for matching")
    except psycopg.OperationalError:
        print(
            f"Warning: Could not connect to database '{dbname}', proceeding without alias resolution"
        )
    print()

    print("# Extraction Comparison Report")
    print()

    # --- Species coverage ---
    base_galls = extract_gall_names(baseline, alias_map)
    ext_galls = extract_gall_names(extracted, alias_map)

    base_set = set(base_galls.keys())
    ext_set = set(ext_galls.keys())
    common = base_set & ext_set
    only_baseline = base_set - ext_set
    only_extracted = ext_set - base_set

    print("## Species Coverage")
    print(f"- Baseline: {len(base_set)} gall species, {len(baseline)} records")
    print(f"- Extracted: {len(ext_set)} gall species, {len(extracted)} records")
    print(f"- In common: {len(common)}")
    print(f"- Only in baseline (missed): {len(only_baseline)}")
    print(f"- Only in extracted (new/extra): {len(only_extracted)}")
    print()

    if common:
        print("### Matched species")
        for name in sorted(common):
            ext_originals = ext_galls.get(name, [])
            base_originals = base_galls.get(name, [])
            if ext_originals != base_originals:
                print(f"  - {name} (extracted as: {ext_originals[0]})")
            else:
                print(f"  - {name}")
        print()

    if only_baseline:
        print("### Missed (in baseline, not extracted)")
        for name in sorted(only_baseline):
            print(f"  - {name}")
        print()

    if only_extracted:
        print("### Extra (extracted, not in baseline)")
        for name in sorted(only_extracted):
            originals = ext_galls.get(name, [])
            print(f"  - {name} (as: {originals[0]})")
        print()

    # --- Host associations ---
    base_pairs = extract_pairs(baseline, alias_map)
    ext_pairs = extract_pairs(extracted, alias_map)

    common_pairs = base_pairs & ext_pairs
    missed_pairs = base_pairs - ext_pairs
    extra_pairs = ext_pairs - base_pairs

    print("## Host Associations")
    print(f"- Baseline pairs: {len(base_pairs)}")
    print(f"- Extracted pairs: {len(ext_pairs)}")
    print(f"- Matching: {len(common_pairs)}")
    print(f"- Missed: {len(missed_pairs)}")
    print(f"- Extra: {len(extra_pairs)}")
    if base_pairs:
        recall = len(common_pairs) / len(base_pairs) * 100
        print(f"- Recall: {recall:.1f}%")
    if ext_pairs:
        precision = len(common_pairs) / len(ext_pairs) * 100
        print(f"- Precision: {precision:.1f}%")
    print()

    # --- Trait comparison ---
    compare_traits(baseline, extracted, alias_map)


if __name__ == "__main__":
    main()
