**CRITICAL**:
- Investigation Before Action
- Search Before You Write
- The most common agent failure is writing new code for something that already exists. Do not do this.
- Do not commit until `mix precommit` passes clean. No exceptions for failures that look pre-existing or unrelated to your change: fix them. A test that fails only sometimes has a cause (timing, data, async race); find it rather than re-running until green.
- Features and bug fixes: write the failing test first and watch it fail for the expected reason, then implement.
- Always compile with `--warnings-as-errors`, never plain `mix compile` (or run `mix precommit`). CI enforces it.

This file (AGENTS.md is the same file) holds rules only, for any agent. Plans, their status and the backlog live in docs (see Work tracking).

## Building

- Before adding a function, component or module, search for one that does the job, and call or extend it. Call the functions your task names; if one doesn't fit, stop and say why. Shared capabilities have one owner (`SingleEntryPoint` in `.credo.exs`).
- Replacing means deleting: add the old module to `test/support/retirements.exs` first, delete it in the same change. Never raise a baseline to pass a check.
- Your hand-back (the report you give Jeff when you finish) lists each new public function, component and module and why nothing existing fit, what you deleted, and what is unverified.
- One piece of work per session: a step of a plan, or a backlog entry. If your context has been summarized or compacted more than once, finish the current task, tell Jeff where the work stands, and stop.

## Before you commit

The pre-commit hook (`dev/githooks/`, installed by `make hooks`) blocks a commit without a passing review. A commit touching only `docs/`, `runbooks/` or the top-level README needs none.

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

- On `taxogall` the code runs on the new back-end (`Catalog`, `Taxa`, `Facts`, `Import`, `Audit`, `Sources`); the plan: `docs/taxogall/`. The old tables stay until cutover, read only by the catalog migration ([general.md](docs/domain/general.md), [admin-domain-reference.md](docs/domain/admin-domain-reference.md)).
- [domain-model.md](docs/domain/domain-model.md) is the domain language being discovered, not software. Don't use it to explain current code, or the old docs to design new work.

## Work tracking

- **Plans are markdown docs, written with Jeff and planned just in time.** A plan is a folder in `docs/` with a README (goals, settled decisions, its phases with what each needs and where it stands) linking one doc per phase. A phase doc gets its detail when that phase is next, not before.
- **Don't change a plan's scope or decisions unless Jeff asks.** Propose changes to him. Record his decisions in the plan doc they shape, with his name and the date.
- **Status lives in the plan docs.** Update a phase's status in the same commit as the work that changes it.
- **Backlog:** a bug or idea that belongs to no plan goes in [docs/backlog.md](docs/backlog.md), one entry each; one that belongs to a plan goes in its phase doc. Add them as you find them, and don't act on them unless Jeff says to. Feedback Jeff hands over for later is recorded the same way, in his words, and never dropped. Planning a phase starts by reading the backlog for entries it should take in.
- **Questions for Jeff:** ask him directly, and keep working on whatever isn't blocked.
- **Each piece of planned work says what it deletes ("Deletes:") and the functions it calls ("Calls:", never "as in X").**
- **Hard checks:** `make done-checks` rebuilds the checkout's test database, then runs `mix precommit` and `mix dialyzer`. Don't call work finished until it passes.
- **Hand-over:** what changed and how it fits, a tour for UI work (what to click and what Jeff should see), and what Jeff must decide. Keep it short.
- **Branches:** short descriptive names. `docs/plans/` is gitignored scratch.

## Old IDs (mull history)

Work used to be tracked in mull, which is retired. Don't run the `mull` CLI, don't create items, and don't add `Mull:` commit trailers or `<id>-` branch names. Cite a commit, PR or plan doc instead.

Old IDs remain throughout code comments, docs, commits and branch names: four hex characters such as "item a44d", "question 96e8" or "matter 16bb". They record why something is the way it is, often in Jeff's words, and are worth reading before changing what they cite. Both stores are read-only history: never edit them.

- **Item, idea, bug, loose end, question or decision `<id>`**: a mull record on the `mull` git branch. Read it with git, without checking the branch out:
  - `git ls-tree -r --name-only mull | grep <id>` finds every file for it.
  - `git show mull:items/<id>.md`: an item, idea or bug (title, plan, phase, stage, and the request).
  - `git show mull:reports/<id>-1.md`: its done report (summary, design notes, tour).
  - `git show mull:inbox/<id>.md`: a question, decision, loose end or review, and its answer.
  - `git show mull:plans/<slug>.md`, `mull:phases/<id>.md` and `mull:docs/`: plans, phases and their docs.
  - `git log --all --grep "Mull: <id>"`: the commits that did it.
- **Matter `<id>`**: the tracker before mull, in `.mull/matters/<id>-*.md` or `.mull/archive/<id>-*.md`. Their statuses are stale.

Incidents: `docs/incidents/`. Procedures: `runbooks/`. AWS (OpenTofu): `infra/`. Setup: [README.md](README.md).
