**CRITICAL**:
- Investigation Before Action
- Search Before You Write
- The most common agent failure is writing new code for something that already exists. Do not do this.
- Do not commit until `mix precommit` passes clean. No exceptions for failures that look pre-existing or unrelated to your change: fix them. A test that fails only sometimes has a cause (timing, data, async race); find it rather than re-running until green.
- Features and bug fixes: write the failing test first and watch it fail for the expected reason, then implement.
- Always compile with `--warnings-as-errors`, never plain `mix compile` (or run `mix precommit`). CI enforces it.

This file holds rules only. Program status goes in matters, detail in the docs it links. Keep it short enough to be read in full.

## Running mix and the databases

- `mix test` and `mix precommit` choose the test environment themselves. Don't prefix them with `MIX_ENV`.
- Other mix commands (`mix run`, `mix gallformers.*` tasks) default to `dev` and act on the dev database. Before running one that writes, know which database it targets; use `MIX_ENV=test` for throwaway scripts.
- The dev shell (`flake.nix`) points `PGHOST`/`PGPORT` at the project's own Postgres 17 on `127.0.0.1:54317`, not a system Postgres on 5432 that may hold databases with the same names. The dev repos refuse to start without `PGPORT` (`Gallformers.Repo.DevShell`). When telling someone where data lives, check with `psql -At -c "select current_setting('port')"`.
- Tests use their own database, one per checkout (`config/test_db_names.exs`), rebuilt by `make test` (`make test-db` to rebuild by hand). It holds `priv/repo/test_seeds.sql` converted by the catalog migration; see [README.md](README.md). Add a test case as old-style seed rows, with their curated decisions in `test/support/fixtures/catalog_migration/`. Look higher taxa up with `Gallformers.Taxa.get_by_legacy_id/2`: their IDs aren't stable.

## Background jobs

Use `Oban` for durable, retryable, or scheduled background work. Reserve plain `GenServer` loops and `Process.send_after/3` for in-memory process behavior where persistence, retries, and operator visibility do not matter. The queue dashboard is at `/admin/jobs`.

## Design system and UI components

**CRITICAL**: All UI follows the design system in **[docs/design-system/](docs/design-system/README.md)**. Read its README before writing or changing any UI. Use its components ([the catalog](docs/design-system/components.md)); do NOT implement custom/inline versions of them. Creating new UI patterns or components requires explicit user approval.

1. **Check the catalog and existing pages** for a component or pattern that fits.
2. **If one almost fits**, extend it (and its catalog entry).
3. **If none fits**, ASK. Write the proposed component's catalog entry for approval; don't build it inline.

The conformance test fails on new off-system styling. Fix the code; never raise its baseline to make it pass. See [CODING_STANDARDS.md](./CODING_STANDARDS.md) for details as needed.

## Domain model

- On `taxogall` the code runs on the new back-end (`Catalog`, `Taxa`, `Facts`, `Import`, `Audit`, `Sources`); its state and what's left is matter `50ff`. The old tables stay until cutover, read only by the catalog migration; [docs/domain/general.md](docs/domain/general.md) and [admin-domain-reference.md](docs/domain/admin-domain-reference.md) describe them.
- [docs/domain/domain-model.md](docs/domain/domain-model.md) is the domain language being discovered for the redesign. It is about the domain, not software, and is not implemented. Don't use it to explain current code, or the old docs to design new work.

## Work tracking: mull is the single source of truth

All work tracking (ideas, plans, research, status) lives in **mull matters**. No plan documents are committed to git: `docs/plans/` is gitignored scratch, and a plan's decisions go into its matter before the session ends, so a future session can pick the work up from the matter alone. Summarize decisions and rationale; don't copy plans verbatim.

- `mull show <id>` to load a matter; `mull add "title" --epic <name>` to capture new work
- `mull append <id> - <<'EOF'` to add body text, always piped via stdin; `--replace` to rewrite the body
- `mull plan <id>` once its plan is agreed; `mull done <id>` when the work is complete

Each plan task says what it deletes ("Deletes:") and the functions it calls ("Calls:", never "as in X"). Code-writing agents are spawned as `builder`. One matter per session.

| Content | Location |
|---------|----------|
| Work tracking, plans, status | Mull matter body |
| Domain model definition | `docs/domain/domain-model.md` |
| Incident docs | `docs/incidents/` |
| Operational procedures | `runbooks/` |
| AWS infrastructure (OpenTofu) | `infra/` |

Setup problems: [README.md](README.md).
