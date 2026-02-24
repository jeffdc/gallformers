# WCVP Reconciliation Pipeline Design

## Overview

An Elixir-based pipeline (Mix tasks) that downloads WCVP (World Checklist of Vascular Plants) data from Kew Royal Botanic Gardens, reconciles it against the gallformers database, produces JSON reports of discrepancies, and optionally applies changes. Replaces the role of the legacy Rust USDA importer for ongoing plant taxonomy maintenance.

## Goals

- Full bidirectional diff: what's in gallformers but not WCVP, and vice versa
- Detect taxonomy mismatches (family/genus disagree between sources)
- Identify range data available from WCVP for existing species
- Separate US/Canada gaps (high priority) from rest-of-hemisphere (growth roadmap)
- Reports committed to git for tracking over time
- Manual trigger now, schedulable later

## Pipeline Architecture

Three phases, each a separate Mix task:

```
WCVP CSV files (Kew SFTP)
        |
        v
 mix gallformers.wcvp.download    Fetch + cache locally
        |
        v
   priv/repo/data/wcvp/
   ├── wcvp_names.csv             (~1.4M rows, ~340k accepted)
   └── wcvp_distributions.csv    (~2M rows)
        |
        v
 mix gallformers.wcvp.reconcile   Compare WCVP <-> gallformers DB
        |
        v
   priv/repo/data/reconciliation/YYYY-MM-DD/
   ├── taxonomy-mismatches.json
   ├── in-gf-not-wcvp.json
   ├── in-wcvp-not-gf-usca.json
   ├── in-wcvp-not-gf-hemisphere.json
   └── range-updates.json
        |
        v
 mix gallformers.wcvp.apply       Apply selected changes from reports
```

The cached WCVP CSVs go in `.gitignore` (large, freely downloadable). Reconciliation reports go in git.

## Name Matching Strategy

WCVP provides pre-parsed fields (genus, species, infraspecific_epithet, taxon_rank, authors are separate columns), so no parser-combinator needed.

**Pass 1 — Exact canonical match**: Compare `"Genus species"` directly. Catches the majority.

**Pass 2 — Genus + epithet fuzzy**: For unmatched gallformers species, try normalized epithet matching (handle `-ii` vs `-i`, `-ensis` vs `-ense`, etc.).

**Pass 3 — Synonym lookup**: WCVP tracks synonyms (each name row has `accepted_kew_id`). If a gallformers name matches a WCVP synonym, report as "gallformers uses synonym X, WCVP accepted name is Y".

**Unmatched**: Anything remaining goes into `in-gf-not-wcvp.json` for manual review.

## TDWG-to-Places Mapping

WCVP distributions use TDWG Level 3 codes (botanical regions). A static mapping file translates these to gallformers place codes.

| Pattern | Example | Mapping | Precision |
|---------|---------|---------|-----------|
| US states | `CAL` → `US-CA` | 1:1 | `exact` |
| CA provinces | `ABT` → `CA-AB` | 1:1 | `exact` |
| Brazil regions | `BZL` → `BR-PR`, `BR-SC`, `BR-RS` | 1:many | `exact` |
| Whole countries | `MEX` → `MX` | 1:1 | `country` |
| Caribbean islands | `CUB` → `CU` | 1:1 | `exact` |

Mapping lives at `priv/repo/data/tdwg_to_places.json`. Hand-curated once (TDWG codes are stable). ~180 TDWG L3 codes cover the Western Hemisphere.

## Report Formats

All reports are JSON arrays. Each item is self-contained (no external lookups needed to understand it).

### taxonomy-mismatches.json

Species exists in both but taxonomy differs.

```json
{
  "gf_species_id": 1234,
  "gf_name": "Quercus parvula",
  "gf_family": "Fagaceae",
  "gf_genus": "Quercus",
  "wcvp_accepted_name": "Quercus parvula",
  "wcvp_family": "Fagaceae",
  "wcvp_genus": "Quercus",
  "wcvp_section": "Quercus sect. Quercus",
  "mismatch_type": "family|genus|synonym",
  "detail": "human-readable description of what differs"
}
```

### in-gf-not-wcvp.json

In gallformers but no WCVP match after all passes.

```json
{
  "gf_species_id": 5678,
  "gf_name": "Somegenus somespecies",
  "gf_family": "Asteraceae",
  "gf_genus": "Somegenus",
  "match_attempts": ["exact", "fuzzy", "synonym"],
  "closest_wcvp_match": "Somegenus somespecies var. foo"
}
```

### in-wcvp-not-gf-usca.json / in-wcvp-not-gf-hemisphere.json

In WCVP but not gallformers. Split by priority: US/Canada (audit gaps) vs rest of hemisphere (growth roadmap).

```json
{
  "wcvp_id": 99999,
  "wcvp_name": "Genus epithet",
  "wcvp_family": "Rosaceae",
  "wcvp_genus": "Genus",
  "wcvp_distribution": ["US-CA", "US-OR"],
  "wcvp_status": "Accepted"
}
```

### range-updates.json

Species matched, WCVP has range data gallformers doesn't.

```json
{
  "gf_species_id": 1234,
  "gf_name": "Quercus alba",
  "current_places": ["US-AL", "US-CT"],
  "wcvp_places": ["US-AL", "US-CT", "MX"],
  "new_places": ["MX"],
  "new_precision": {"MX": "country"}
}
```

## Apply Commands

```bash
# Dry run (default) - preview what would change
mix gallformers.wcvp.apply priv/repo/data/reconciliation/2026-02-19/range-updates.json

# Apply changes
mix gallformers.wcvp.apply priv/repo/data/reconciliation/2026-02-19/range-updates.json --commit

# Cherry-pick specific species
mix gallformers.wcvp.apply priv/repo/data/reconciliation/2026-02-19/range-updates.json --commit --ids 1234,5678
```

All writes go through existing context functions (Plants, Ranges, Taxonomy) so validations, PubSub, and FTS indexing fire normally. Dry run is always the default.

Taxonomy mismatch apply updates taxonomy linkage (re-points species_taxonomy). Species renames are manual operations, not automated.

## Module Organization

```
lib/mix/tasks/gallformers/wcvp/
├── download.ex       # Mix.Tasks.Gallformers.Wcvp.Download
├── reconcile.ex      # Mix.Tasks.Gallformers.Wcvp.Reconcile
└── apply.ex          # Mix.Tasks.Gallformers.Wcvp.Apply

lib/gallformers/wcvp/
├── reader.ex         # CSV parsing, streaming, filtering to accepted names
├── matcher.ex        # Name matching (exact, fuzzy, synonym)
├── tdwg.ex           # TDWG-to-places mapping
└── reporter.ex       # Report generation (JSON output)
```

## Data Files

```
priv/repo/data/
├── wcvp/                          # .gitignored - cached WCVP downloads
│   ├── wcvp_names.csv
│   └── wcvp_distributions.csv
├── tdwg_to_places.json            # Static mapping, committed
└── reconciliation/                # Reports, committed
    └── YYYY-MM-DD/
        ├── taxonomy-mismatches.json
        ├── in-gf-not-wcvp.json
        ├── in-wcvp-not-gf-usca.json
        ├── in-wcvp-not-gf-hemisphere.json
        └── range-updates.json
```
