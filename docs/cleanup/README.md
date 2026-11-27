# Cleanup

The plan for getting Gallformers' planning, docs and branches under control: moving off mull, setting up docs-based planning for taxogall, and clearing out what's stale. This is the one plan we run in detail now; everything else is planned just in time. It changes as the work does.

The model is the oaks repo (`~/dev/oaks/docs`): a plan is a folder with an overview README (goals, settled decisions, a phase table with needs and status) linking one doc per phase; work outside any plan goes in `docs/backlog.md`; the architecture is described as built in `docs/architecture/`. Mull is retired there, and old IDs are read with git.

## Goals

- **Plan just in time** (Jeff, 2026-11-26). Mull's detail (176 committed items) was too much to be useful. Taxogall gets one high-level plan doc that points to child plans, each written when it's next. Only this cleanup is planned in detail now.
- **Mull is retired** in gallformers as in oaks. Its records stay readable with git (AGENTS.md, "Old IDs"); what's still live is brought into a plan doc or the backlog when it's needed, not copied over wholesale.
- **Every branch has a known status** and an agreed fate.
- **The docs are current or clearly history,** and `docs/plans/` scratch is gone through.
- **One step at a time,** each small enough to review in one sitting.

Done when:

- `docs/taxogall/README.md` exists: the high-level plan, pointing to its child plans, with its first step being to revisit the phases.
- `docs/backlog.md` holds the bugs and ideas that belong to no plan.
- No instruction, tool, hook or setting tells an agent to use mull.
- Every branch is merged, deleted, or listed with a reason to keep it.
- `docs/plans/` is triaged, and the committed docs are current or marked as history.

## Target shape

| Where | What | Modelled on |
|---|---|---|
| `docs/cleanup/README.md` | This plan | |
| `docs/taxogall/README.md` | Taxogall's high-level plan: goals, principles, settled decisions, the child plans with needs and status | oaks `facts-expansion/README.md` |
| `docs/taxogall/<child>.md` | One per child plan, written when it's next | oaks `facts-expansion/*.md` |
| `docs/backlog.md` | Bugs and ideas outside any plan (stub created) | oaks `backlog.md` |
| `docs/architecture/` | Current state, rules, decisions, reviews (later) | oaks `architecture/` |

## Steps

Each step is reviewed by Jeff before the next starts.

| # | Step | Status |
|---|---|---|
| 1 | Lay of the land and this plan | Done (2026-11-26) |
| 2 | Retire mull's instructions: AGENTS.md / CLAUDE.md (docs-based work tracking, "Old IDs"), the Makefile comment, the project's Claude settings | Done (2026-11-26) |
| 3 | Branches: delete the fully merged ones; move work onto `taxogall`; keep v1's last commit as the tag `archive/v1-final` | Done (2026-11-26) |
| 4 | Branches: go through the unmerged ones one by one, find what each is, decide | Next |
| 5 | Taxogall's high-level plan: `docs/taxogall/README.md` from mull's plan doc, checked against the 2026-11 reboot presentation; its first child step is revisiting mull's 18 phases | Not started |
| 6 | Backlog: mull's 27 unphased items and its captured bugs and ideas, only what's still live | Not started |
| 7 | Mull's 22 unsettled inbox entries (17 decisions, 4 questions, 1 review): each to Jeff, into the taxogall plan, or dropped | Not started |
| 8 | `docs/plans/` scratch: a big pass, in batches (fold in, keep as history, or delete with Jeff's OK) | Not started; plan the batches when it starts |
| 9 | Committed docs: current, update, or history; old-model docs, research, presentations, `docs/5c56-interview-summary.md`; stale mull pointers such as `docs/domain/domain-model.md`'s "design draft lives in mull matter 8567" | Not started |
| 10 | Architecture docs in the oaks shape | Later; may become its own plan |

## Lay of the land (scanned 2026-11-26)

### Mull (the `mull` branch, read-only now)

- **Plans:** `taxogall` (its doc is about 190 lines) and `general` (done).
- **Phases:** 18, each with a phase doc (about 1,060 lines in all): Decisions first; The UI; Review cleanup; Housekeeping; Import at scale; Public site, settled; One write path; Ranges; Migration through the import; Migration data; One editor; Gall relationships; Gallformers notes; Preview environment; Collecting Source documents; Process Sources on preview; Rehearse and cut over; After release.
- **Items:** 219: 176 committed, 21 captured, 6 done, 1 in review (5352, the notes analysis), 15 dropped. 27 have no phase, mostly production bugs and repo housekeeping.
- **Inbox:** 302 entries: 132 decisions, 132 questions, 24 loose ends, 7 ideas, 7 reviews. 22 unsettled.
- **Old tracker (`.mull/`):** 68 matters left open (statuses stale), 116 archived.

### Branches

`main` and `origin/main` match (2026-10-27). `taxogall` is ahead of `main` by about 175 commits and 4 behind; local and origin match.

Deleted 2026-11-26: `5352-notes-analysis` (same commit as `taxogall`), `origin/llm-lit-poc`, `origin/source-ingestion`, and `origin/v1-final` once its commit (`c662f9c1`, 2026-02-04) was tagged `archive/v1-final` (Jeff: a tag, since a branch can move and looks like clutter). Already gone from origin when we looked: the dependabot branches, `fix-admin-live-session-auth`, `fix-content-image-upload-events`, `nix-dev-shell`, `s3-refactor`, `retire-old-source-ingestion`, `security-dependency-fixes`, and origin's copies of `postgres-migration`, `python-ingestion-pipeline` and `feature/safer-admin-deletes`.

Still to go through (step 4):

| Branch | Last commit | Commits not on main | Where | First look |
|---|---|---|---|---|
| alpha-ui | 2026-05-21 | 39 | local, origin | |
| workspace-gall-editor | 2026-05-09 | 26 | local, origin | |
| postgres-migration | 2026-03-15 | 18 | local | Postgres is live, so likely superseded |
| python-ingestion-pipeline | 2026-05-15 | 17 | local, worktree in `.worktrees/` | The old ingestion was retired |
| phenology-release | 2026-09-08 | 14 | local | Draft PR #578 (Megachile) |
| quercus-leafminer-key | 2026-09-08 | 2 | local | One key commit |
| feature/safer-admin-deletes | 2026-09-02 | 1 | local | |
| beads-sync | 2026-02-12 | 611 | origin | The tracker before old mull |
| chore/js-deps-update, chore/python-deps-update | 2026-07-27 | 1 each | origin | |

Kept: `main`, `taxogall`, `mull` (history). Open PRs: #598 "Move browser tests to Fluffy" (ftes), #578 (draft).

### Docs

- **Committed:** `docs/architecture/`, `docs/design-system/`, `docs/domain/` (the domain model, plus `general.md` and `admin-domain-reference.md` describing the old model), `docs/import/`, `docs/ops/`, `docs/elixir/`, `docs/research/` (early-2026 proposals and audits), `docs/presentations/`, `docs/incidents/`, `docs/security/`, `docs/testing-philosophy.md`, `docs/database.md`, `docs/5c56-interview-summary.md`. `runbooks/` has 16, some assuming the old tables.
- **`docs/plans/` (gitignored):** about 100 entries: item bodies and appends, designs from February, the 2026-11-12 history audit, the taxonomy migration research (with raw iNat API dumps), the 5352 notes-analysis scripts and samples, design-system shots.

### Mull references left on purpose

Citations of old IDs in incidents, presentations, `priv/import/README.md` and `services/import-producer/README.md` are history and stay; AGENTS.md says how to read them. `/.mull/` in `.dockerignore` stays while the directory does. Your global `~/.claude/settings.json` still allows `Bash(mull *)`; that's outside this repo, so it's yours to decide.

## Open questions for Jeff

None open.

## Log

- **2026-11-26:** Scanned mull, `.mull/`, docs and branches; wrote this plan. Jeff: plan just in time; taxogall gets one high-level doc pointing to child plans, whose first step is revisiting the phases; delete merged branches; go through unmerged ones one by one; move to `taxogall`; `docs/plans/` needs a big pass; retire every mull instruction. Did steps 2 and 3.
- **2026-11-26:** Pushed `taxogall`. Tagged v1's last commit `archive/v1-final` and deleted the branch. Committed step 2 after the commit gate's review.
