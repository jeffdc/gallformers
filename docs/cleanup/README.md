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
| 5 | Taxogall's high-level plan: [`docs/taxogall/README.md`](../taxogall/README.md) from mull's plan doc, checked against the 2026-11 reboot presentation; its first child step is revisiting mull's 18 phases | Done (2026-11-26) |
| 6 | Architecture baseline (a fresh session): [`docs/architecture/`](../architecture/README.md) in the oaks shape, mapped from `taxogall` (see below) | Done (2026-11-26) |
| 7 | Backlog: mull's 27 unphased items and its captured bugs and ideas, only what's still live | Done (2026-11-27) |
| 8 | Mull's 22 unsettled inbox entries (17 decisions, 4 questions, 1 review): each to Jeff, into the taxogall plan, or dropped | Done (2026-11-27) |
| 9 | `docs/plans/` scratch: a big pass, in [six batches](#step-9-docsplans-in-batches) (fold in, keep as history, or delete with Jeff's OK) | Done (2026-11-27) |
| 10 | Committed docs: current, update, or history; old-model docs, research, presentations, `docs/5c56-interview-summary.md`; stale mull pointers such as `docs/domain/domain-model.md`'s "design draft lives in mull matter 8567"; the domain doc updated to Jeff's 2026-11-15/16 decisions (Host ranges, observed range, Traits by Host) and organised into the doc set | In progress: [planned in seven batches](#step-10-committed-docs-in-batches); batches 1 and 2 done (2026-11-27) |
| 11 | Adopt the architecture reviewer from heartwood (see below) | Ready: heartwood v0.1.1 tagged 2026-11-26 (bf622eb); starts with the backlog's move onto `heartwood_guardrails` |

**Why this order.** Mull's instructions went first so no session writes to it while it's extracted. The taxogall plan comes next, then the architecture baseline: knowing what's built tells us which docs are current, so the docs passes (9, 10) come after it. Branches, the backlog and the inbox can go in any order.

### Step 6: architecture baseline

Asked for by Jeff through the oaks session, 2026-11-26: gallformers adopts the architecture model oaks set up (`~/dev/oaks/docs/architecture/`, and section 5 of `~/dev/oaks/docs/facts-expansion/architecture-groundwork.md`).

- **The shape:** `docs/architecture/README.md` describes the architecture and design as built, and only what's built (system context, runtime, contexts and the tables each owns, the dependency graph from `mix xref`, data, web layer, front end and design system, delivery, observability); planned work moves in when it lands, in the same commit as the code. `rules.md` holds only rules Jeff has stated, each with its source, a stable ID by group, its check (or "manual") and a baseline of violations with locations. `decisions.md` is a decision log, newest first, never edited, superseded by later entries. `reviews.md` has one entry per periodic review; each finding ends as fix, accept, new rule or open. DESIGN.md stays the authority on the look; coding style stays in CODING_STANDARDS and Credo.
- **What's "built" is `taxogall`** (Jeff, 2026-11-26), with a note that production (`main`) runs the old back-end until cutover.
- **Architecture docs live in one place** (Jeff, 2026-11-26). Pull what's still true from the existing docs as the new ones are written, then delete the old ones: `core-architecture-rules.md`'s principles and enforcement become rules; `elixir-architecture.md` is a tutorial and moves out to `docs/elixir/` or goes; `range-system.md` is likely out of date and is revisited in full; the C4 Structurizr model is dropped (never used).
- **Decisions are seeded judiciously** (Jeff, 2026-11-26): only those that shape the architecture, dated, citing their mull or matter ID. Many established decisions live in the existing docs and in the system itself (Boundary config, Credo checks, ratchets), not only in mull. The rest of mull's decisions stay readable with git.
- **Checks gallformers already has** become rules' checks: Boundary, the custom Credo checks, the design-system and duplicate-code ratchets, `test/support/retirements.exs`, the commit gate, CI.
- **Mapping:** four read-only agents in parallel, as in oaks: (1) contexts, their tables and the xref graph folded into contexts, with every reach into another context's tables; (2) the web layer: router, auth, LiveViews, components, assets, API; (3) runtime, infra and delivery: Fly, OpenTofu/AWS, Oban, S3, preview; (4) every existing check, and the documented rules no check covers, each with a baseline. From that: README, rules, decisions and a first review entry (violations, gaps in the checks, proposed rules, drift between docs and code).

### Step 9: `docs/plans/` in batches

Planned 2026-11-27. `docs/plans/` holds 103 entries (348 files, 15 MB), all gitignored and local to Jeff's checkout. Each batch is one sitting: check each entry, propose its fate, and act on Jeff's OK. A fate is one of: fold what's still live into a committed doc (the taxogall plan, the backlog, the domain or architecture docs), keep as history, or delete. History stays where it is, local and gitignored, as the matters that cite these files expect (Jeff, 2026-11-27). Kept: `5352-gallformers-notes-analysis.md` and `5352-notes-analysis/`, the notes analysis Jeff is reviewing.

| # | Batch | Entries | Proposed fate |
|---|---|---|---|
| 1 | Drafts of old-tracker matters: `<id>-body`, `-append`, `-status`, `-plan` files for 1121, 20e5, 294c, 2c8c, 3272, 36ca, 6611, 6ee3, 803b, 86e7, 9380, 9449, a856, b119, b4d8, d213, d585, e381 | 32 | Delete. Each one's text is in its committed `.mull/` matter, line for line, or as an earlier status the matter later settled (803b's open questions, 294c's wording review, 9449's and 9380's notes) |
| 2 | One-off queries, outputs and scripts: `qt_*` (14), the trial and rerun shell scripts (7), `2026-10-30-notes-review.sql`, `coupling_inventory.py`, `extract_design.py`, `search_transcript.py`, `catalog/` (the 2026-10-26 rehearsal worksheets, 9 MB; the migration rewrites them on any run), `.DS_Store` | 27 | Delete |
| 3 | Mockups and design working files: `disputes-step`, `galls-step`, `names-step`, `source-review`, `review-redesign`, `term-questions` (and its `.src`) HTML, and `design-system/` (direction source, Playwright scripts, before-shots) | 8 | Check each against what's built and its published artifact; delete what's built or dropped |
| 4 | Before taxogall (2026-02 to 05): Postgres research, admin reconciliation UI, continent scoping, global expansion, preview as production mirror, utils/tree cleanup, `plan1`/`plan2` (the May ingestion pipeline), the changeset audit prompt | 9 | Check each: done, superseded, or a live idea for the backlog |
| 5 | Taxogall design history (2026-10): discovery notes, the domain model's v1 snapshot, the two-systems matter, 8567's drafts, 0b's Sources–Facts notes, e381 v2, 294c's schema, step 3 plan and wording review, 8546's trial, 9449's rehearsal, the schema design and plan, step 10's body, the top-level matter body, the review UI requirements, and the taxonomy migration research (raw iNat API dumps) | 20 | Check each against the taxogall plan, the domain doc and the architecture docs; fold what's live (some overlaps step 10), the rest history or delete |
| 6 | Notes, queue and audit work (2026-10 to 11): the notes sample and notes review, the queue triage, the 2026-11-12 history audit, the API users list | 5 | Check each; the notes work against 5352. `2026-11-16-api-users.md` holds API users' contact details, kept out of git on purpose: it stays local until the contact before release (open: whether it moves somewhere safer) |

### Step 10: committed docs in batches

Planned 2026-11-27. About 90 committed docs under `docs/` (outside this plan, the taxogall plan, the backlog and `docs/architecture/`), `runbooks/`, and the top-level and `infra/` READMEs. Each batch is one sitting: check each doc, propose its fate, and act on Jeff's OK. A fate is one of: current (no change), update, mark as history (a banner saying what it describes and when), or delete.

**The doc set** (Jeff, 2026-11-27): the domain doc holds our shared language; the architecture docs hold the technical landscape and the guardrails (the design system counts as architecture); plans hold the detail needed to execute, and age out and go away. So the only long-term durable docs are the domain and architecture docs: living docs we must keep aligned, written for humans to understand, not only agents. A curator guide is user documentation, durable too and kept aligned with the domain doc (Jeff, 2026-11-27). A range from Hosts is the *potential* range, not "predicted"; the domain doc names each Trait and points to the vocabulary for its values, which grow over time (Jeff, 2026-11-27).
 The [baseline review](../architecture/reviews.md#doc-drift)'s doc drift items 2, 5, 6 and 7 are fixed here. The only live mull pointer left is `domain-model.md`'s banner; the old IDs cited in incidents, presentations and decisions are history and stay (AGENTS.md, "Old IDs").

| # | Batch | Docs | Proposed fate |
|---|---|---|---|
| 1 | The domain doc | `docs/domain/domain-model.md` | Done (2026-11-27). Update to Jeff's 2026-11-15/16 decisions as the [taxogall plan](../taxogall/README.md) records them: Host ranges are Facts on the plant; the observed range is occurrence Facts (the observational data and observed range lines came from discovery note D5 and go); Traits never vary by Host; the generation groups; the banner's mull pointer. Then organise it into the doc set: the taxogall plan's domain rules move into it, and the plan points there |
| 2 | Old-model docs | `docs/domain/general.md`, `admin-domain-reference.md`, `taxonomy.md`, `admin-onboarding.md`, `admin-release-notes-reclassify-taxa.md`, `docs/5c56-interview-summary.md` | Done (2026-11-27). They describe production (`main`) until cutover, and their replacement is after-release work. Mark each as history of the old model, or delete what nothing needs; check 5c56 for input to the taxonomy API design |
| 3 | Research and presentations | `docs/research/` (8 docs and the GallOnt ontology), `docs/presentations/` (the February roadmaps, Woodend, the November reboot, the range screencast outline) | Presentations are dated and stay as history. Research: history or delete, each checked for a live idea for the backlog (phenology, keys, GallOnt) |
| 4 | Engineering docs with known drift | `AGENTS.md`'s domain doc line ("being discovered, not software. Don't use it to explain current code"), `CODING_STANDARDS.md`, `docs/testing-philosophy.md`, `docs/design-system/README.md` and `components.md`, `docs/database.md`, `docs/ops/`, `docs/elixir/` | Update for drift items 2, 5 and 6, and AGENTS.md's Dialyzer claim; `docs/elixir/` is a tutorial, kept or deleted |
| 5 | Runbooks, README and infra | `runbooks/` (16 and the SQL), the top-level `README.md`, `infra/README.md` | Update for drift item 7 (ewr, the VM, self-managed Postgres, Oban's queues, backups, `services/usda_plants`, the workflow names, the public dump, what `infra/README.md` leaves out); the runbooks that assume the old tables say so; `postgres-cutover.md` (closed 2026-03-25) becomes history |
| 6 | The rest | `docs/design-system/` (other than batch 4's), `docs/import/`, `DESIGN.md`, `PRODUCT.md`, `docs/incidents/`, `docs/security/` | Check the design system and import docs are current; incidents and the security note are history by nature and stay as they are |
| 7 | The taxogall plan's technical decisions | `docs/taxogall/README.md`'s settled decisions (one write path, audit, two systems, IDs, change events, natural keys, the tree tables) | Check each against `docs/architecture/`; where the architecture docs hold it, the plan points there and keeps only what the work needs |

### Step 11: architecture reviewer

Its shape is decided (Jeff, 2026-11-26, in oaks' `docs/facts-expansion/architecture-groundwork.md`, section 5); it is in `heartwood_guardrails` v0.1.1 (tagged on bf622eb, jeffdc/heartwood#5), beside the reuse review; its CHANGELOG entry has the optional upgrade steps and its README the section "The architecture review". Oaks is moving to v0.1.1 and can serve as a reference setup.

- `mix heartwood.architecture` (test env) writes the packet: the `mix xref` graph folded to contexts, every ratchet in `config :heartwood_guardrails, ratchets:` against its baseline, the commits since the last review (those after the last commit that changed `reviews.md`), `mix heartwood.status`, the architecture docs and the app's own questions. `review/architect.md` is the prompt, any model, read-only; `bin/record-architecture <model> -` keeps one report per model per run in git's common directory (`gallformers-architecture/<date-and-HEAD>/<model>.md`), shared by every worktree, nothing to gitignore. Jeff combines a run's reports into one `reviews.md` entry.
- The task graphs the Mix project it runs in (the repo root). Gallformers sets in `dev/guardrails/config.sh` its architecture docs (default `docs/architecture/`), its questions for the reviewer (default `dev/guardrails/architecture.md`) and `HEARTWOOD_GRAPH_DEPTH` (default 3: how many path segments name a context, so `lib/gallformers/taxa.ex` and `lib/gallformers/taxa/ancestry.ex` both fold to `lib/gallformers/taxa`).
- For the full review (all optional): `"heartwood.architecture": :test` in `preferred_envs` in `cli/0`; the ratchets listed in `config :heartwood_guardrails, ratchets: [...]` (`config/test.exs`), since the packet shows only those; the questions written in `dev/guardrails/architecture.md`. `mix heartwood.architecture` prints the packet's path (`<git common dir>/gallformers-architecture/<date>-<sha>/packet.md`); each model records with `deps/heartwood_guardrails/guardrails/bin/record-architecture <run> <model> -`.
- It needs `heartwood_guardrails` as a dependency (the [backlog](../backlog.md)'s heartwood entry). Under v0.1.0 a `sparse:` dependency sits at `deps/heartwood_guardrails/guardrails`, not where the shim and README say; v0.1.1 fixes it. Until then set `HEARTWOOD_HOME=deps/heartwood_guardrails/guardrails` in `config.sh` and use that path for the hooks, `bin/review-packet` and `bin/check-toolchain`; with v0.1.1, copy `hooks/app-shim` again and the workaround goes.

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
- **2026-11-26:** Step 5 done: wrote [the taxogall plan](../taxogall/README.md). Jeff: held edits in a change set are how editing works today; the domain doc is to be updated and organised into the doc set (step 10); nothing else is built until the house is in order, so the plan's first child is this cleanup; the plan links to mull's phases rather than listing them, since revisiting them reads each in detail.
- **2026-11-26:** Step 6 done: wrote [`docs/architecture/`](../architecture/README.md) (README as built on `taxogall`, rules with their checks and baselines, a decision log seeded with 15 decisions, and the [baseline review](../architecture/reviews.md#2026-11-26-baseline)), mapped by four read-only agents. Deleted `core-architecture-rules.md`, `range-system.md`, `elixir-architecture.md` (a tutorial whose examples described contexts that no longer exist) and the C4 model, with Jeff's OK. Jeff: every bug the review found goes in the [backlog](../backlog.md), and planning a phase starts by reading the backlog. The review's doc drift outside `docs/architecture/` is for step 10.
- **2026-11-27:** Step 7 done: brought 27 of mull's items into the [backlog](../backlog.md), each checked against the code and citing its item; a short item is carried whole, a long one summarised with a pointer to mull. Jeff: the backlog is the one place to look, so captured items filed under taxogall phases come over too; drop the credential rotation (14b2); switch from Auth0 to Oak Compendium's model for identity and access (a new idea that takes in 5975). Of the 27 unphased, 11 are live and came over (b8ef folded into the dev-uploads bug it fixes); 14b2 was dropped by Jeff; 10 were already dropped in mull and stay dropped; 5 are done or moot (b472 built; 5b9a, 5f73 and 9090 cleared in steps 3 and 4; 1cc4, `main`'s broken e2e suite, is fixed on `taxogall` and lands with the merge, and the browser tests are rebuilt after cutover). All 16 captured items filed under taxogall phases are live and came over with their phase named, for the phase revisit; the phases' 165 committed items stay in mull until that revisit (Jeff, 2026-11-27).
- **2026-11-27:** Step 8 done, with Jeff. Into the [taxogall plan](../taxogall/README.md)'s open design work: the 10 taxonomy rules built in phase 2 (under the taxonomy API) and the 3 built curation rules (under editing), for Jeff's review there; the judgement-notes question (2ac6, under the notes); vocabulary curation at scale (1878, 542d) as a new item. Dropped: 0b79, answered by Jeff's 2026-11-16 ranges decision, with the code's gap filed in the [backlog](../backlog.md); 28bf, superseded by undescribed-Gall notes being processed as Sources; 5352's four method decisions, history in mull. The 5352 review stays with Jeff as the plan's notes item in review.
- **2026-11-27:** Step 9 started: [planned the `docs/plans/` pass](#step-9-docsplans-in-batches) in six batches. Jeff: what's kept as history stays in `docs/plans/`, local; delete batches 1 and 2. Deleted their 59 entries, leaving 44 (5.4 MB).
- **2026-11-27:** Batch 3 done: every mockup is built and the design direction became `docs/design-system/`, so Jeff OK'd deleting all 8 entries. Jeff: code shouldn't refer to a mock, so the review code's two citations of `review-redesign.html` went (ade37dbc). 36 entries left (4.0 MB).
- **2026-11-27:** Batch 4 done, with Jeff's OK: deleted all nine. The Postgres research and the preview-as-mirror rehearsal plan (the cutover closed 2026-03-25), global expansion and continent scoping (shipped in #518), the admin reconciliation UI (7932 done; WCVP data now arrives as Facts), the utils/tree cleanup (its modules are gone) and `plan1`/`plan2` (the May pipeline, replaced by the import contract) were done or moot; the changeset audit prompt became a [backlog](../backlog.md) idea first. 27 entries left (3.9 MB).
- **2026-11-27:** Batch 6 done, with Jeff. Deleted the notes sample and notes review list (superseded by 5352's analysis on a newer snapshot) and the queue triage (summarised in a856; the queue was redesigned). Kept as local history: the 2026-11-12 history audit, whose section B (Jeff's agent rules that live nowhere) became a [backlog](../backlog.md) entry for Jeff to go through, and `2026-11-16-api-users.md`, local because it holds contact details. 24 entries left (3.8 MB); batch 5 is next, in a fresh session.
- **2026-11-27:** Batch 5 done, with Jeff; step 9 done. Deleted 15, each an older copy of its committed matter or settled since: 8567's design draft, v2 and coupling inventory, 0b's Sources–Facts notes, the two-systems matter draft, e381 v2, 294c's schema and step 3 plan, the schema design and plan and the first rehearsal (9449), 8546's trial plan, step 10's body (a856), the top-level matter body (50ff), and the review UI requirements (6611, built). Kept as local history: the domain model's v1 snapshot (cited by the domain doc and 8567), 294c's wording review (cited by 294c), and the taxonomy migration research (cited by b5bd); and, for Jeff to look at, the discovery notes (his verbatim domain answers) and 8567's ordering and relationships analysis (reasoning for the two-systems decision that's in no committed doc). Folded into the [taxogall plan](../taxogall/README.md)'s open design work, at Jeff's OK: the prior art in iNaturalist's taxon-change code, for the taxonomy API, and the v1 snapshot's "who it serves", as input to the Gallformers overview for Jeff to confirm. For step 10: the domain doc's observational data and observed range lines ("without a Fact per Observation", "Observed range … Future") came from discovery note D5 and are superseded by Jeff's 2026-11-16 ranges decision (an observed range is occurrence Facts); rewrite them from the taxogall plan, not from the notes. Left in `docs/plans/`: those 5, the 2026-11-12 history audit, `2026-11-16-api-users.md`, and 5352's notes analysis (2 entries), 9 entries in all (3.6 MB).
- **2026-11-27:** Step 10 started: [planned the committed docs pass](#step-10-committed-docs-in-batches) in seven batches. Jeff set the doc set: the domain and architecture docs are the durable, living docs, kept aligned and written for humans; plans hold what's needed to execute and age out. Batch 1 done: rewrote the [domain doc](../domain/domain-model.md) to his 2026-11-14 to 11-17 decisions (plants, curated and imported taxa, taxonomic acts, Gall names, the two Gallformers Sources, what is a Fact and what is editorial, attribution, standings, ranges as potential and observed with occurrences, Traits never by Host, generation groups, the alternate-generation flags, the curator), with the Trait values pointing to the vocabulary and a list of where each decision came from; the [taxogall plan](../taxogall/README.md)'s settled decisions point to it instead of repeating them. Jeff: the word is *potential* range; the [backlog](../backlog.md)'s ranges entry now uses it. The plan's technical decisions against the architecture docs became batch 7, and AGENTS.md's line on the domain doc joined batch 4.
- **2026-11-27:** Step 10's batch 2 done, with Jeff's OK. Deleted `docs/domain/taxonomy.md` (the old taxonomy system) and the spring release notes for production admins. `general.md` and `admin-domain-reference.md` stay until cutover with a banner saying they describe the old model, for the catalog migration's sake; the taxogall plan now deletes them after release, since the domain doc replaces them. The admin guide is marked out of date (Edit mode, the dropped flags, *absent from*); Jeff: a curator guide is user documentation, and its rewrite is part of the plan's Gallformers overview. Folded Adam's 2026-02-22 merge and split interview (5c56) and deleted it: plant splits and lumps reaching their Galls into the plan's taxonomy API item; the merge's copy step and the iNat mismatch queue into the [backlog](../backlog.md), under their release gates.
