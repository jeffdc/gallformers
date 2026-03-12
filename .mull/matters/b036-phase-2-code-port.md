---
status: done
created: 2026-03-11
updated: 2026-03-12
epic: postgres
blocks: [1c9b]
needs: [f654]
parent: 4474
---

# Phase 2: Code port

## Goal

All application code running against Postgres. No SQLite-specific code remaining in the main app (WCVP repo excluded). Tests green. Docs updated.

## Phase 1 Intel (failure inventory from test baseline)

~290 total test failures, but only ~90 are root causes. ~200 are cascading (BadMapError/MatchError from nil query results, `in_failed_sql_transaction` from poisoned sandbox transactions). Fix the roots and the cascade clears.

### Root-cause failures by category

| Category | Count | Grep for | Fix direction |
|----------|-------|----------|---------------|
| `nocase` collation | 35 | `fragment.*nocase`, `collate: :nocase` | `citext` extension or `lower()` |
| `COALESCE bool/int` | 25 | `COALESCE` in Ecto fragments | `COALESCE(field, false)` not `COALESCE(field, 0)` |
| `INSERT OR IGNORE/REPLACE` | 14 | `INSERT OR` in raw SQL | `ON CONFLICT DO NOTHING` / `DO UPDATE` |
| `json_each(text)` | 7 | `json_each` in fragments | `jsonb_each` or `jsonb_array_elements` |
| Untyped `?` params | ~5 | `?` in recursive CTE fragments | Add `?::integer` casts |
| Date string encoding | 3 | Test helpers inserting date strings | Pass `%Date{}` structs |
| Constraint name mismatches | ~27 | `unique_constraint` in changesets | Match Postgres naming convention |

### Gotchas discovered during Phase 1

- **NOT NULL timestamps enforced strictly** — SQLite allowed NULL even with NOT NULL. Any raw SQL inserting without `inserted_at`/`updated_at` will fail.
- **Boolean strictness is pervasive** — not just seeds. Application-level `COALESCE(field, 0)` where field is boolean breaks.
- **`Gallformers.Migration` module is SQLite-specific** — `@disable_ddl_transaction true`, `safe_recreate_table/2`. Needs removal (Step 3).
- **`species.taxonomy_id` is dead** — doesn't exist in Postgres schema. Code referencing it will break.
- **WCVP repo stays SQLite** — `ecto_sqlite3` remains a dep. Don't remove it.
- **Async tests already enabled** — 58 files, no concurrency bugs found, runtime 2.7s.

### What Phase 1 already handled

- Test seeds ported (booleans, timestamps, FTS inserts removed)
- Makefile targets working against Postgres
- CI workflow for `postgres-migration` branch
- Async tests enabled

## Steps

### 1. Mechanical query port
- `fragment("lower(?) LIKE ?")` → `ilike` (39 occurrences in 8 app files)
- `GROUP_CONCAT` → `string_agg` (2 files: ranges.ex, species.ex)
- `fragment("date(?)")` in analytics.ex (3 calls) — verify if Postgres handles `date()` as a type cast or if it needs `::date`. Fix if needed.
- `COALESCE(bool_field, 0)` → `COALESCE(bool_field, false)` (25 failures)
- `INSERT OR IGNORE/REPLACE` → `ON CONFLICT` syntax (14 failures)
- `json_each(text)` → Postgres JSON functions (7 failures)
- Untyped `?` params in recursive CTEs → add `?::integer` casts (~5 failures)
- Fix Date string encoding in test helpers (3 failures)
- Fix constraint name mismatches in changesets (~27 failures)
- `nocase` collation → `citext` or `lower()` comparisons (35 failures)
- Any other SQLite-specific fragments identified during the work

### 2. FTS migration
- Postgres tsvector column on species table with GIN index
- Database triggers to auto-sync on species INSERT/UPDATE and alias changes
- Rewrite search queries in search.ex, species.ex, plants.ex
- Remove manual FTS sync infrastructure: `update_species_fts/1`, `delete_species_fts/1`, `rebuild_species_fts/0`, all call sites
- Remove `sanitize_fts_query/1` (replace with Postgres tsquery construction)
- Update test seeds — FTS inserts already removed in Phase 1, add tsvector population
- Search quality verified manually

### 3. Remove SQLite workarounds
- Delete `lib/gallformers/migration.ex` (safe_recreate_table module)
- Delete all old migration files (19 files) — baseline migration from Phase 0 replaces them. Old files `use Gallformers.Migration` and won't compile once the module is deleted.
- Delete `lib/mix/tasks/migrations/lint.ex` (migration linter)
- Remove `busy_timeout` config from all environments
- Remove `journal_mode: :wal` config from all environments
- Remove Litestream from Dockerfile and entrypoint
- Remove `litestream.yml`
- Remove kill_timeout Litestream flush logic
- Clean up any other SQLite-specific code paths

### 4. Documentation updates
- Update CLAUDE.md — remove all SQLite-specific caveats, add Postgres patterns
- Update CODING_STANDARDS.md — remove SQLite section, update query patterns, update test infrastructure docs
- Update README.md — dev setup instructions now require local Postgres
- Update any other docs referencing SQLite, Litestream, single-writer, busy_timeout, WAL mode, etc.
- Update runbooks as needed

## Output
- All tests pass against Postgres
- CI green
- No SQLite-specific code in main app
- FTS working with trigger-based sync
- All documentation current
