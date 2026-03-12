---
status: done
created: 2026-03-11
updated: 2026-03-12
epic: postgres
blocks: [b036]
needs: [f6bb]
parent: 4474
---

# Phase 1: Dev + CI workflow

## Goal

Development loop functional against Postgres: local Makefile targets work, CI pipeline exists. Tests will NOT fully pass yet — SQLite-specific code (FTS, GROUP_CONCAT) still in the codebase. Phase 2 gets tests green.

## Steps

### 1. Local CI (Makefile)
- Get all Makefile targets operational against Postgres
- `make test` — rebuilds test DB (now via `mix ecto.create && mix ecto.migrate && psql < test_seeds.sql`), runs tests
- `make precommit` — format, credo, compile --warnings-as-errors, tests
- Other targets: `make test-db`, `make ci`, etc.
- Test seeds ported from SQLite-flavored SQL to Postgres-compatible SQL
- Note: test seeds currently INSERT INTO `species_fts` — must be removed/rewritten since FTS5 virtual table won't exist in Postgres
- `make download-db` deferred — not needed during migration work (conversion tool from Phase 0 covers it)
- CI must support BOTH Postgres (main Repo) and SQLite (WCVP Repo) — WCVP tests need SQLite available

### 2. Enable async tests
- Remove `max_cases: 1` from `test_helper.exs`
- Remove `async: false` enforcement from DataCase and ConnCase
- Set `async: true` on test files (55 files)
- Fix any tests that break under concurrency — shared state assumptions, insertion order dependencies, etc.
- Risk: some tests may have implicit ordering dependencies that only surface under concurrency

### 3. GitHub Actions CI
- Separate workflow file for the integration branch (not modifying existing workflow)
- Postgres service container
- SQLite also available (needed for WCVP tests)
- Test seeds loaded via psql
- Scoped to integration branch via `on.push.branches` / `on.pull_request.branches`
- When migration merges to main: swap in as the primary workflow, delete old SQLite workflow

## Exit criteria
- Makefile targets run (some tests will fail due to SQLite-specific code — that's expected)
- Async test infrastructure in place
- CI pipeline exists and runs on the integration branch
- Phase 2 will get tests fully green

## Goal

Development loop functional against Postgres: local Makefile targets work, CI pipeline exists. Tests will NOT fully pass yet — SQLite-specific code (FTS, GROUP_CONCAT) still in the codebase. Phase 2 gets tests green.

## Context from Phase 0

- **test_seeds.sql** has `INSERT INTO species_fts` lines (lines 61-72, 159-160, 178-179, 225-227) that will fail against Postgres. Must be removed.
- **`Gallformers.Migration` module is SQLite-specific** — sets `@disable_ddl_transaction true` and provides `safe_recreate_table/2`. The baseline migration uses plain `Ecto.Migration`. Any code doing `use Gallformers.Migration` needs updating (more Phase 2 than Phase 1).
- **`source.licenselink`** is `:text` in the migration but `:string` in the Ecto schema (Ecto uses `:string` for both). Correct — just worth knowing.
- **9 gallhost + 65 species_source duplicates** in prod SQLite — conversion tool deduplicates them. Postgres schema has unique constraints SQLite didn't enforce.
- **`species.taxonomy_id`** is a dead column in SQLite (all NULL), doesn't exist in Postgres. Any code referencing it will break.
- **WCVP repo stays SQLite** — `ecto_sqlite3` remains a dependency. CI needs both database engines available.
- **Conversion tool**: `mix convert_sqlite` loads prod data into Postgres. Repeatable — run anytime after `mix ecto.reset`.

## Steps

### 1. Local CI (Makefile)
- Get all Makefile targets operational against Postgres
- `make test` — rebuilds test DB (now via `mix ecto.create && mix ecto.migrate && psql < test_seeds.sql`), runs tests
- `make precommit` — format, credo, compile --warnings-as-errors, tests
- Other targets: `make test-db`, `make ci`, etc.
- Test seeds ported from SQLite-flavored SQL to Postgres-compatible SQL
- Note: test seeds currently INSERT INTO `species_fts` — must be removed/rewritten since FTS5 virtual table won't exist in Postgres
- `make download-db` deferred — not needed during migration work (conversion tool from Phase 0 covers it)
- CI must support BOTH Postgres (main Repo) and SQLite (WCVP Repo) — WCVP tests need SQLite available

### 2. Enable async tests
- Remove `max_cases: 1` from `test_helper.exs`
- Remove `async: false` enforcement from DataCase and ConnCase
- Set `async: true` on test files (55 files)
- Fix any tests that break under concurrency — shared state assumptions, insertion order dependencies, etc.
- Risk: some tests may have implicit ordering dependencies that only surface under concurrency

### 3. GitHub Actions CI
- Separate workflow file for the integration branch (not modifying existing workflow)
- Postgres service container
- SQLite also available (needed for WCVP tests)
- Test seeds loaded via psql
- Scoped to integration branch via `on.push.branches` / `on.pull_request.branches`
- When migration merges to main: swap in as the primary workflow, delete old SQLite workflow

## Exit criteria
- Makefile targets run (some tests will fail due to SQLite-specific code — that's expected)
- Async test infrastructure in place
- CI pipeline exists and runs on the integration branch
- Phase 2 will get tests fully green
