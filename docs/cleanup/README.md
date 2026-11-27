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
| `docs/architecture/` | The one place for architecture docs: `README.md` (as built), `rules.md`, `decisions.md`, `reviews.md` | oaks `architecture/` |

## Steps

Each step is reviewed by Jeff before the next starts.

| # | Step | Status |
|---|---|---|
| 1 | Lay of the land and this plan | Done (2026-11-26) |
| 2 | Retire mull's instructions: AGENTS.md / CLAUDE.md (docs-based work tracking, "Old IDs"), the Makefile comment, the project's Claude settings | Done (2026-11-26) |
| 3 | Branches: delete the fully merged ones; move work onto `taxogall`; keep v1's last commit as the tag `archive/v1-final` | Done (2026-11-26) |
| 4 | Branches: go through the unmerged ones one by one, find what each is, decide | Done (2026-11-26) |
| 5 | Taxogall's high-level plan: `docs/taxogall/README.md` from mull's plan doc, checked against the 2026-11 reboot presentation; its first child step is revisiting mull's 18 phases | Not started |
| 6 | Architecture baseline (a fresh session): `docs/architecture/` in the oaks shape, mapped from `taxogall` (see below) | Not started |
| 7 | Backlog: mull's 27 unphased items and its captured bugs and ideas, only what's still live | Not started |
| 8 | Mull's 22 unsettled inbox entries (17 decisions, 4 questions, 1 review): each to Jeff, into the taxogall plan, or dropped | Not started |
| 9 | `docs/plans/` scratch: a big pass, in batches (fold in, keep as history, or delete with Jeff's OK) | Not started; plan the batches when it starts |
| 10 | Committed docs: current, update, or history; old-model docs, research, presentations, `docs/5c56-interview-summary.md`; stale mull pointers such as `docs/domain/domain-model.md`'s "design draft lives in mull matter 8567" | Not started |
| 11 | Adopt the architecture reviewer (prompt, packet script, local reports) once oaks settles it, possibly shared through heartwood | Waits for oaks |

**Why this order.** Mull's instructions went first so no session writes to it while it's extracted. The taxogall plan comes next, then the architecture baseline: knowing what's built tells us which docs are current, so the docs passes (9, 10) come after it. Branches, the backlog and the inbox can go in any order.

### Step 6: architecture baseline

Asked for by Jeff through the oaks session, 2026-11-26: gallformers adopts the architecture model oaks set up (`~/dev/oaks/docs/architecture/`, and section 5 of `~/dev/oaks/docs/facts-expansion/architecture-groundwork.md`).

- **The shape:** `docs/architecture/README.md` describes the architecture and design as built, and only what's built (system context, runtime, contexts and the tables each owns, the dependency graph from `mix xref`, data, web layer, front end and design system, delivery, observability); planned work moves in when it lands, in the same commit as the code. `rules.md` holds only rules Jeff has stated, each with its source, a stable ID by group, its check (or "manual") and a baseline of violations with locations. `decisions.md` is a decision log, newest first, never edited, superseded by later entries. `reviews.md` has one entry per periodic review; each finding ends as fix, accept, new rule or open. DESIGN.md stays the authority on the look; coding style stays in CODING_STANDARDS and Credo.
- **What's "built" is `taxogall`** (Jeff, 2026-11-26), with a note that production (`main`) runs the old back-end until cutover.
- **Architecture docs live in one place** (Jeff, 2026-11-26). Pull what's still true from the existing docs as the new ones are written, then delete the old ones: `core-architecture-rules.md`'s principles and enforcement become rules; `elixir-architecture.md` is a tutorial and moves out to `docs/elixir/` or goes; `range-system.md` is likely out of date and is revisited in full; the C4 Structurizr model is dropped (never used).
- **Decisions are seeded judiciously** (Jeff, 2026-11-26): only those that shape the architecture, dated, citing their mull or matter ID. Many established decisions live in the existing docs and in the system itself (Boundary config, Credo checks, ratchets), not only in mull. The rest of mull's decisions stay readable with git.
- **Checks gallformers already has** become rules' checks: Boundary, the custom Credo checks, the design-system and duplicate-code ratchets, `test/support/retirements.exs`, the commit gate, CI.
- **Mapping:** four read-only agents in parallel, as in oaks: (1) contexts, their tables and the xref graph folded into contexts, with every reach into another context's tables; (2) the web layer: router, auth, LiveViews, components, assets, API; (3) runtime, infra and delivery: Fly, OpenTofu/AWS, Oban, S3, preview; (4) every existing check, and the documented rules no check covers, each with a baseline. From that: README, rules, decisions and a first review entry (violations, gaps in the checks, proposed rules, drift between docs and code).

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

Gone through one by one and deleted, 2026-11-26 (Jeff), none tagged:

- `alpha-ui` and `workspace-gall-editor` (a strict subset of it): the old LLM source-ingestion pipeline and its review workspace (May 2026; matters 83b9, 415f, 6c67, f037). Superseded by the import contract, the producer and the importer; its design work was judged not worth keeping.
- `python-ingestion-pipeline` and its worktree: the Python half of the same retired pipeline (matter c744).
- `postgres-migration`: landed on `main` in another form; the cutover closed 2026-03-25.
- `phenology-release`: a local copy of Megachile's draft PR #578 (the phenology explorer, built on the old model). The PR stays open on Megachile's fork; for the backlog (step 7): port it to the new model after cutover.
- `quercus-leafminer-key`: Eiseman's leafminer key as JSON, never imported; leafminers aren't galls, and it's kept in another project.
- `feature/safer-admin-deletes`: landed on `main` (`dangerous_delete_modal`), and carried on in `taxogall`.
- `beads-sync`: the beads tracker's sync branch from before old mull.
- `chore/js-deps-update`, `chore/python-deps-update`: stale lockfile updates from July, the second for the retired `services/source-ingestion`.

Kept: `main`, `taxogall`, `mull` (history), and the tags `archive/v1-final` and `archive/elixir-snapshot-2026-05-16`. No worktrees. Open PRs: #598 "Move browser tests to Fluffy" (ftes), #578 (draft).

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
- **2026-11-26:** Added the architecture baseline (step 6) and adopting the reviewer (step 11), at Jeff's request through the oaks session; Jeff settled its shape.
- **2026-11-26:** Step 4 done: every unmerged branch gone through with Jeff and deleted.
