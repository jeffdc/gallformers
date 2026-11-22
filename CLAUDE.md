**CRITICAL**:
- Investigation Before Action
- Search Before You Write
- The most common agent failure is writing new code for something that already exists. Do not do this.
- Do not commit until `mix precommit` passes clean. No exceptions for failures that look pre-existing or unrelated to your change: fix them. A test that fails only sometimes has a cause (timing, data, async race); find it rather than re-running until green.
- Features and bug fixes: write the failing test first and watch it fail for the expected reason, then implement.
- Always compile with `--warnings-as-errors`, never plain `mix compile` (or run `mix precommit`). CI enforces it.

This file (AGENTS.md is the same file) holds rules only, for any agent. Status lives in mull, detail in the docs its plans, phases and items link.

## Building

- Before adding a function, component or module, search for one that does the job, and call or extend it. Call the functions your task names; if one doesn't fit, stop and say why. Shared capabilities have one owner (`SingleEntryPoint` in `.credo.exs`).
- Replacing means deleting: add the old module to `test/support/retirements.exs` first, delete it in the same change. Never raise a baseline to pass a check.
- Your hand-back (the design notes you give `mull done`) lists each new public function, component and module and why nothing existing fit, what you deleted, and what is unverified.
- One mull item per session. If your context has been summarized or compacted more than once, finish the current task, tell Jeff where the item stands, and stop.

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

- On `taxogall` the code runs on the new back-end (`Catalog`, `Taxa`, `Facts`, `Import`, `Audit`, `Sources`); state: the `taxogall` plan in mull (`mull plan show taxogall`). The old tables stay until cutover, read only by the catalog migration ([general.md](docs/domain/general.md), [admin-domain-reference.md](docs/domain/admin-domain-reference.md)).
- [domain-model.md](docs/domain/domain-model.md) is the domain language being discovered, not software. Don't use it to explain current code, or the old docs to design new work.

## Work tracking

Plans, work items, the backlog and questions for Jeff live in mull, not in committed plan docs (`docs/plans/` is gitignored scratch).

- **Plans:** `taxogall` (Galls and Facts, through cutover). Small work outside it is unplanned (`--plan none`).
- **Hard checks:** `make done-checks`, which `mull done` runs: it rebuilds the checkout's test database, then runs `mix precommit` and `mix dialyzer`.
- **Layers** for done reports (`mull config`): `ui` (`lib/gallformers_web`, `assets`, `dev/gallformers_web`; tours required), `domain`, `data`, `import`, `tests`, `docs`, `tooling`.
- **Old tracker:** `.mull/` is read-only history. "Matter xxxx" in code, notes or entries means `ls .mull/*/xxxx-*`. Don't edit it or track work there.
- Each item's notes say what it deletes ("Deletes:") and the functions it calls ("Calls:", never "as in X").

## Working with mull

This project's plans, work items, backlog and open questions live in **mull**: a CLI whose data sits on the `mull` git branch. Use only the CLI. Never read or edit mull's data or the `mull` branch directly.

- **Output.** Every command prints JSON, and errors are `{"code", "error"}` on stderr. `mull guide json` documents the shapes and error codes.
- **Batch.** To write more than a couple of records, use `mull batch` (JSON Lines on stdin, all or nothing) instead of a shell loop.
- **The record.** Plans hold phases, and phases hold items. An item goes captured → committed → active → in review → done, or is dropped. Captured items (bugs and ideas) are the backlog: they aren't work until the human commits them. Done means reviewed.

1. **Start of session:** run `mull context --item <id>`, or `mull context` if you have no item yet.
   - Read the decisions it lists, and don't re-decide anything the log already settles.
   - Read the item's `docs` and its `phase_doc` (the phase's design and when it's done). Docs hold intent only. Status comes from mull, never from a doc.
2. **One item per session.**
   - Claim it with `mull start <id>`. Your item is committed work (`mull ready`), or a captured item the human wants done now: starting commits it.
   - Work on a branch named `<id>-<short-name>`.
   - End every commit message with the trailer line `Mull: <id>`.
3. **Capture as you go,** one line each, without waiting for the end. Anyone captures; only the human commits.
   - `mull decided "<what you chose>" --item <id> --detail "<why, one line>"`: any choice the human didn't make for you.
   - `mull ask "<question>" --item <id>`: anything you need from the human. Keep working on whatever isn't blocked.
   - `mull bug "<what>" --source "item <id>"`: anything out of scope that's wrong (a bug, an inconsistency, half-finished work, an assumption you made).
   - `mull idea "<title>" --detail "<short note>" --source "<where>"`: a possibility worth keeping that isn't work yet, whether the human raised it or you noticed it. Keep to ideas worth the human's time.
   - Bugs and ideas go to the backlog, not to the human's inbox: that's only questions, decisions and reviews. The human goes through the backlog in triage (`mull guide triage`). Add `--plan` or `--phase` to a capture if it belongs to one, and `--category` if it helps.
   - **Feedback the human hands over for later** (something to fix, change or revisit, but not now):
     ```
     mull bug "<the feedback, in the human's words>" --source "human, <date or context>"
     ```
     - File it when it's given. Don't hold it for the end of the session.
     - Don't act on it in your current work unless the human says to, and never drop it.
     - It's feedback if it judges or asks to change existing work. It's an idea if it's a possibility that isn't work yet. If you can't tell which, ask the human.
4. **Don't change plans or phases (or their docs), and don't add items,** unless the human asks. Propose changes with `mull ask`.
   - Only the human creates and agrees a plan (`mull plan new ... --on-request`, `mull plan agree <slug> --on-request`). A plan that's still shaping takes captures and questions, but no phases or committed work.
   - Read a plan's or phase's doc with `mull plan doc <slug>` or `mull phase doc <id>`.
   - Order exists only between phases (`mull need <phase> <phase>`). Items inside a phase are unordered.
   - Never commit a captured item (`mull commit <id>`) on your own. When the human tells you to, add `--on-request`, with `--plan`, `--phase` or `--plan none` if they say where it goes. Retag a capture (`mull set <id> plan|phase <value>`) only on their word too.
5. **Finish only with `mull done`:**
   ```
   mull done <id> --summary "<what changed and how it fits>" --tour "<steps, or none>" --design -
   ```
   - Give the design notes on stdin: how you built it and why (the approach, the shape of the code, what you rejected). They're required, and "none" isn't accepted.
   - Give the tour inline, one step per line: what to click and what the human should see. Write "none" if no UI changed. Only one of `--summary`, `--tour` and `--design` can read stdin.
   - `done` runs the project's hard checks itself. If they fail, fix the problem and run `done` again, or run `mull release <id>` and say why.
   - After `done` the item is in review. It's done only once its review is accepted. Never say an item is done unless `mull done` succeeded.
6. **Hand over:**
   - Show the human (or the supervisor) the report from `mull report <id>`, and the tour. The review carries the decisions you recorded with `--item`, and accepting it ratifies them.
   - Run `mull accept <id> --on-request` only when the human tells you to. If they decide one of those decisions differently, run `mull decide <decision-id> "<their decision>" --on-request` first.
   - Settle any other inbox entry only on the human's explicit instruction, also with `--on-request`.
7. **Run `mull sync`** after `done` and at the end of the session.

Incidents: `docs/incidents/`. Procedures: `runbooks/`. AWS (OpenTofu): `infra/`. Setup: [README.md](README.md).
