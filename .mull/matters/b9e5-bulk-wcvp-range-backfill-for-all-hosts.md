---
status: planned
created: 2026-03-02
updated: 2026-03-10
epic: geo-expansion
relates: [d7d1, 8900, f6d4, be9d, 2dc1, 383e, 0df8]
blocks: [f6d4]
docket: true
---

# Bulk WCVP range backfill for all hosts

## Problem

Host species in the prod DB lack WCVP-sourced range data. The existing admin flow handles one host at a time. We need a bulk approach for all ~2,180 hosts. Only 62 currently have a wcvp_id in host_traits.

## Approach: Local generation, prod SQL execution

Generate a self-contained SQL file locally, SFTP to prod, execute via sqlite3 CLI. Single transaction, minimal write lock time, no Mix/Ecto on prod.

## Pipeline

### Phase 0: Prepare mappings (done once, human-reviewed)

0.1. `make download-db` — fresh prod snapshot
0.2. `mix gallformers.wcvp.reconcile` — generates reconciliation reports
0.3. `mix gallformers.wcvp.backfill mappings` — generates mappings CSV + unmatched report
0.4. Human reviews CSV: mark fuzzy rows A or R. Save.
0.5. Share unmatched hosts report with fellow admins.

### Phase 1: Generate SQL (at go time)

1.1. `make download-db` — fresh prod snapshot (again)
1.2. `mix gallformers.wcvp.backfill check --csv path/to/mappings.csv` — drift check
1.3. `mix gallformers.wcvp.backfill generate --csv path/to/reviewed-mappings.csv` — generates .sql

### Phase 2: Apply to prod

2.1. SFTP `.sql` to Fly machine
2.2. `sqlite3 /data/gallformers.sqlite < backfill.sql` via SSH

## Mappings CSV format

```
species_id,species_name,wcvp_plant_name_id,wcvp_name,match_type,decision
4521,Quercus alba,12345,Quercus alba,exact,
4530,Rubus pensylvanicus,67890,Rubus pensilvanicus,fuzzy,
4535,Salix sp.,,,none,X
```

Decision column: blank = auto-accept (exact), A = accept fuzzy, R = reject fuzzy, X = ignore (none).
Unreviewed fuzzy rows (blank decision) error at SQL generation time.

## Design decisions

- **Additive only**: `INSERT OR IGNORE` — never removes existing range data
- **Single transaction**: One write lock acquisition, fast execution
- **CSV for review**: Spreadsheet-friendly, simple A/R/X decisions
- **Drift check before apply**: Catches changes between mapping creation and execution
- **host_traits backfill included**: Writes wcvp_id/powo_id alongside ranges so future per-host WCVP refresh works

## Implementation Plan

**Goal:** Build the `mix gallformers.wcvp.backfill` task with three subcommands (mappings, check, generate) to enable bulk WCVP range backfill via reviewed CSV → SQL pipeline.

**Architecture:** Single Mix task module with subcommand dispatch. Reuses existing `Wcvp.Matcher`, `Wcvp.Reader`, `Wcvp.Tdwg`, and `Wcvp.Lookup` modules. Reconcile output (JSON reports) is the input; the new task transforms it into reviewable CSV, validates it, and generates SQL. Output files go to `priv/repo/data/reconciliation/<date>/`.

### Task 1: Extend reconcile to output all-matches report

**Files:**
- Modify: `lib/mix/tasks/gallformers/wcvp/reconcile.ex` (add `all-matches.json` to report output)

**Behavior:**
The reconcile task already builds a `matches` list with `%{gf_id, gf_name, wcvp_id}` but only uses it internally for range updates. Add `match_type` (`:exact`, `:fuzzy`, `:synonym`) to each match entry during classification, and write the full list as `all-matches.json` alongside the existing reports. Include the WCVP taxon_name so the CSV generator doesn't need to re-look it up.

Output format per entry: `{gf_species_id, gf_name, wcvp_plant_name_id, wcvp_name, match_type}`.

**Testing:**
- Reconcile produces `all-matches.json` in the report directory
- Each entry has all required fields
- match_type is one of "exact", "fuzzy", "synonym"
- Count of all-matches + in-gf-not-wcvp = total GF plants

**Notes:**
The classify_match functions already know the match type — just need to tag the match map before appending. Minimal change to existing code.

### Task 2: `mix gallformers.wcvp.backfill mappings` subcommand

**Files:**
- Create: `lib/mix/tasks/gallformers/wcvp/backfill.ex`
- Test: `test/mix/tasks/gallformers/wcvp/backfill_test.exs`

**Behavior:**
Reads reconciliation reports from the most recent run (or `--run YYYY-MM-DD`):
- `all-matches.json` → CSV rows with match_type, decision blank for exact, blank for fuzzy/synonym (pending review)
- `in-gf-not-wcvp.json` → CSV rows with match_type "none", decision pre-filled "X"

Outputs to the same reconciliation date directory:
- `mappings.csv` — full CSV with all hosts
- `unmatched-hosts.md` — markdown report of none-match hosts, grouped by pattern:
  - "sp." entries (genus-only, no species epithet)
  - Undescribed species
  - Everything else
  - Each entry has: species name, family, genus, admin link (`https://gallformers.org/admin/hosts/{id}`)

**Testing:**
- Produces CSV with correct headers and row count matching total hosts
- Exact matches have blank decision column
- Fuzzy/synonym matches have blank decision (pending review)
- None matches have "X" decision
- Unmatched report groups entries by pattern
- Handles CSV-unsafe characters in species names (commas in names — unlikely but guard against it)

**Notes:**
Use NimbleCSV or manual CSV generation (species names shouldn't contain commas, but quote fields defensively). The unmatched report is informational only — it doesn't feed into the SQL pipeline.

### Task 3: `mix gallformers.wcvp.backfill check` subcommand

**Files:**
- Modify: `lib/mix/tasks/gallformers/wcvp/backfill.ex`
- Test: `test/mix/tasks/gallformers/wcvp/backfill_test.exs`

**Behavior:**
Takes `--csv path/to/mappings.csv`. Loads current hosts from DB. Compares:
- **New hosts**: species_id in DB but not in CSV → "N new hosts not in mappings"
- **Deleted hosts**: species_id in CSV but not in DB → "N hosts in mappings no longer in DB"
- **Renamed hosts**: species_id matches but name differs → "N hosts renamed since mappings created"

Prints a summary report. Exits with non-zero status if any drift found (so it's scriptable). Use `--force` to continue despite drift.

**Testing:**
- Detects new hosts added since CSV was created
- Detects deleted hosts
- Detects renamed hosts
- Exits non-zero on drift (without --force)
- Exits zero when no drift

### Task 4: `mix gallformers.wcvp.backfill generate` subcommand

**Files:**
- Modify: `lib/mix/tasks/gallformers/wcvp/backfill.ex`
- Test: `test/mix/tasks/gallformers/wcvp/backfill_test.exs`

**Behavior:**
Takes `--csv path/to/reviewed-mappings.csv`. Runs drift check first (errors if drift, unless --force).

For each row where decision allows inclusion (blank for exact, A for fuzzy/synonym):
1. Look up WCVP entry via `Wcvp.Lookup.get(wcvp_plant_name_id)` to get native distribution (TDWG codes)
2. Convert TDWG codes to place codes via `Wcvp.Tdwg`
3. Resolve place codes to place_ids via DB query on `place` table
4. Generate `INSERT OR IGNORE INTO host_range` values
5. Generate `INSERT OR REPLACE INTO host_traits` values (wcvp_id + powo_id)

Errors on any unreviewed fuzzy/synonym row (blank decision on non-exact match_type).

Outputs `backfill-YYYY-MM-DD.sql` to the reconciliation directory. Wraps everything in `BEGIN;`/`COMMIT;`.

Prints summary: N hosts processed, N range inserts generated, N host_traits upserts, N skipped (R/X).

**Testing:**
- Generates valid SQL with BEGIN/COMMIT wrapper
- INSERT OR IGNORE for host_range rows
- INSERT OR REPLACE for host_traits rows
- Skips rows with R or X decision
- Errors on unreviewed fuzzy rows
- Resolves TDWG codes correctly (use known TDWG→place mappings in test)
- Handles hosts with no WCVP distribution data (skip gracefully)
- place codes not found in DB are warned and skipped

**Notes:**
The place code → place_id resolution needs to happen against the local DB (which is a copy of prod). Build a lookup map once: `%{"US-AL" => 42, ...}` from the place table. The SQL file should be self-contained — no dependencies on Elixir at execution time.

### Task 5: Cleanup audit

**Files:**
- Potentially remove or modify several WCVP modules after backfill is applied

**Behavior:**
After the backfill is applied to prod, audit for dead code:
- `Wcvp.Reports` + `ReconciliationLive` — still useful? Reports are local-only. If we keep running reconcile periodically, these stay. If not, remove.
- `mix gallformers.wcvp.apply` — superseded by the SQL approach for bulk operations, but may still be useful for targeted one-off updates.
- `mix gallformers.wcvp.backfill_ids` — fully superseded; the generate subcommand writes host_traits directly.

This is a decision task, not a code task. Defer until after backfill is applied and we see what's still needed.

## Dependency order

Task 1 → Task 2 → Task 3 → Task 4 → (apply to prod) → Task 5

Tasks 3 and 4 share a file but task 4 depends on task 3's check logic.
