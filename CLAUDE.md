**CRITICAL**:
- Investigation Before Action
- Search Before You Write
- The most common agent failure is writing new code for something that already exists. Do not do this.
- Do not commit until `mix precommit` passes clean. No exceptions for failures that look pre-existing or unrelated to your change: fix them. A test that fails only sometimes has a cause (timing, data, async race); find it rather than re-running until green.
- Features and bug fixes: write the failing test first and watch it fail for the expected reason, then implement.
- Always compile with `--warnings-as-errors`, never plain `mix compile` (or run `mix precommit`). CI enforces it.

This file (AGENTS.md is the same file) holds rules only, for any agent. Status goes in matters, detail in the docs it links.

## Building

- Before adding a function, component or module, search for one that does the job, and call or extend it. Call the functions your task names; if one doesn't fit, stop and say why. Shared capabilities have one owner (`SingleEntryPoint` in `.credo.exs`).
- Replacing means deleting: add the old module to `test/support/retirements.exs` first, delete it in the same change. Never raise a baseline to pass a check.
- Your hand-back lists each new public function, component and module and why nothing existing fit, what you deleted, and what is unverified.
- One matter per session. If your context has been summarized or compacted more than once, finish the current task, record where it stands in its matter, and stop.

## Before you commit

The pre-commit hook (`dev/githooks/`, installed by `make hooks`) blocks a commit without a passing review.

1. Stage files by name, then run `dev/guardrails/review_packet.sh`.
2. A reviewer with fresh context, not yours, follows `dev/guardrails/reviewer.md` on the packet and records its verdict.
3. On block: fix, restage, review again. Never re-run the review for a different answer; disputes go to Jeff.
4. Commit once it passes.

Never force-push, and never push main or master; the pre-push hook blocks both.

## Running mix and the databases

- `mix test` and `mix precommit` choose the test environment themselves; don't prefix them with `MIX_ENV`. Other mix commands default to `dev` and its database: know which database a writing command targets; use `MIX_ENV=test` for throwaway scripts.
- The dev shell (`flake.nix`) points `PGHOST`/`PGPORT` at the project's Postgres 17 on `127.0.0.1:54317`, not a system Postgres on 5432 with the same database names. Check with `psql -At -c "select current_setting('port')"`.
- Tests use their own database per checkout (`config/test_db_names.exs`), rebuilt by `make test` (`make test-db` by hand): `priv/repo/test_seeds.sql` converted by the catalog migration ([README.md](README.md)). Add a test case as old-style seed rows, curated decisions in `test/support/fixtures/catalog_migration/`. Look higher taxa up with `Gallformers.Taxa.get_by_legacy_id/2`: their IDs aren't stable.

Use `Oban` for durable, retryable or scheduled work (dashboard `/admin/jobs`); plain `GenServer` or `Process.send_after/3` only where persistence and retries don't matter.

## Design system

**CRITICAL**: All UI follows [docs/design-system/](docs/design-system/README.md); read its README first. Check its components ([catalog](docs/design-system/components.md)) and existing pages; never build custom inline versions. If one almost fits, extend it and its entry; if none fits, ASK, with a proposed catalog entry. Never raise the conformance baseline. Details: [CODING_STANDARDS.md](./CODING_STANDARDS.md).

## Domain model

- On `taxogall` the code runs on the new back-end (`Catalog`, `Taxa`, `Facts`, `Import`, `Audit`, `Sources`); state: matter `50ff`. The old tables stay until cutover, read only by the catalog migration ([general.md](docs/domain/general.md), [admin-domain-reference.md](docs/domain/admin-domain-reference.md)).
- [domain-model.md](docs/domain/domain-model.md) is the domain language being discovered, not software. Don't use it to explain current code, or the old docs to design new work.

## Work tracking: mull matters only

Ideas, plans, research and status live in mull matters, not committed plan docs (`docs/plans/` is gitignored scratch). Before the session ends, a plan's decisions and rationale go into its matter, so a fresh session can pick the work up from it alone; don't copy plans verbatim.

- `mull show <id>`; `mull add "title" --epic <name>`; `mull plan <id>`; `mull done <id>`
- `mull append <id> - <<'EOF'` to add body text, always via stdin; `--replace` rewrites it

Each plan task says what it deletes ("Deletes:") and the functions it calls ("Calls:", never "as in X").

Incidents: `docs/incidents/`. Procedures: `runbooks/`. AWS (OpenTofu): `infra/`. Setup: [README.md](README.md).
