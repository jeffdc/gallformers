---
status: planned
created: 2026-11-09
updated: 2026-11-09
epic: platform
relates: [6611, cb28, b016, b230]
---

# Guardrails that hold: stop duplicate code and half-finished replacements

# Guardrails that hold: stop duplicate code and half-finished replacements

## Why

From 2026-11-06 to 11-08 the taxogall review work (`6611`, `cb28`) outran its plans and guardrails. It left duplicate code (two WCVP searches, two iNat searches, two question UIs on one back end) and replacements left half done (the old step and Facts pages still routed). CLAUDE.md already said "Search Before You Write", and the rule was broken anyway. So these guardrails fail the build or block the commit. Written rules are kept to a minimum. The cleanup of what's already there is `b230` (the slop audit); this matter adds the guardrails only.

## Decisions (Jeff, 2026-11-09)

- Today's duplicates get a shrink-only baseline. `b230` cleans them up.
- The reviewer runs on Sonnet 5.5. Its gate is a hard block.
- CLAUDE.md is trimmed and kept under 5,000 bytes.

## Done

- **CLAUDE.md trimmed** from 7,763 to 4,698 bytes (uncommitted). It had grown back from 4.0 KB since the April trim, a line or two per feature commit: taxogall status, detail already held in other docs, and rules moved out of memory. All rules kept; status replaced by a pointer to `50ff`; detail replaced by links. Dropped the seed-ID line (it invited hard-coded IDs, which `NoHardcodedIds` forbids) and the `mull rm` line.

## Tasks

Each lands test-first, with a test proving it fails on a known bad case, and `mix precommit` clean. Together they add about 3 seconds to precommit.

### 1. Duplicate-code check with a shrink-only baseline

- `.credo.exs` gets a second config, `duplicates`: `Credo.Check.Design.DuplicatedCode`, `mass_threshold: 40`, over `lib/` and `test/`. The default config doesn't run it, so `credo --strict` is unchanged.
- `test/gallformers/guardrails/duplicate_code_test.exs` runs that config through `Credo.run/1`, reads `Credo.Execution.get_issues/1`, and groups the findings by their set of files.
  - It fails when a group occurs more often than `test/support/duplicate_code_baseline.json` allows, or occurs and isn't in the baseline.
  - It also fails when the baseline allows more than occurs, so a cleanup is locked in.
  - Same shape as the design-system conformance test.
- `mix gallformers.guardrails.baseline` writes the baseline. It's run once for today's code, and after each `b230` cleanup.
- Today: 11 pairs in `lib/`, about 20 groups in `test/`. Cost: 2.4 seconds.
- Proof: a test that a block copied between two fixture files is reported.

### 2. One entry point per capability

`dev/credo/checks/architecture/single_entry_point.ex`, enabled in the default config, reads its capabilities from its params in `.credo.exs`. That's the only place the allowlist lives.

- **What it matches:** remote calls to the named functions, including calls made through a behaviour accessor such as `wcvp_lookup().search(...)`.
- **What it flags:** a call from any module other than the owner.
- **Pending callers:** each capability has a `pending` list of today's other callers, each with `b230`. The check also fails when a pending module no longer makes the call, so the list can only shrink.

| Capability | Functions | Scope | Owner | Pending (cleaned up in `b230`) |
|---|---|---|---|---|
| WCVP name search | `search/2`, `search_contains/2` on `Wcvp.Lookup` and `wcvp_lookup()` | `lib/gallformers_web/` | `GallformersWeb.Choices` (new `wcvp_plants/2`) | `ReviewLive.Answer`, `TaxonomyLive.New`, `TaxonomyLive.RangeEditor` |
| iNat taxon search | `Import.search_inat_taxa/1` | `lib/gallformers_web/` | `GallformersWeb.Choices` (new `inat_taxa/1`) | `ReviewLive.Answer`, `InatTaxonPanel` |
| Host choices | `Taxa.host_choices/2` | `lib/gallformers_web/` | `GallformersWeb.Choices` | `ReviewLive.Answer` |
| Review decisions | `Import.decide_queue_item/3`, `Import.decide_group/3` | `lib/gallformers_web/` | `ReviewLive.Answer` | `ReviewLive.Review` (batch Accept) |
| Taxon creation | `Taxa.create_taxon/2` | all of `lib/` | `Import`, `Import.ApplyTaxonomy`, `CatalogMigration.*` | none |

Cost: within `credo --strict`, under a second. Proof: a test that a new direct `wcvp_lookup().search/2` call from a LiveView is reported, and that a pending entry whose call is gone is reported.

### 3. Retirements fail the build

- `test/support/retirements.exs` lists `%{retire: Module, replaced_by: Module, matter: "id"}`.
- `test/gallformers/guardrails/retirements_test.exs` fails while both modules of an entry exist.
- Lands with an empty list and a test of the checker on a made-up entry.
- **Rule:** a task that builds a replacement adds its entry first, as its failing test, and deletes the old module in the same commit.
- 6611 Task 10 starts by adding `ItemRow`, `ReviewLive.Step` and `ReviewLive.Facts`, each replaced by `ReviewLive.Review`. While an entry is outstanding nothing else can be committed, which is how one feature's cleanup gets finished before the next starts.

### 4. Reviewer agent and commit gate

- **`.claude/agents/reuse-reviewer.md`:**
  - `model: sonnet`; tools: Read, Grep, Glob, and Bash for the two scripts below.
  - Standing question: what in this diff already exists in the codebase? It also asks: does a replacement here leave its old code in place, and does a commit outside a taxogall cleanup add to CLAUDE.md?
  - It reads the code itself, not the author's summary.
  - Its report lists each finding with the path of the existing code, then a verdict.
- **What blocks:** a finding that names existing code the diff duplicates, or a replacement without its deletion. Everything else is noted and passes.
- **`dev/guardrails/review_packet.sh`** writes the staged diff and the new public functions, components and modules (pulled from the diff, so not the author's account) to `.git/gallformers-review/packet.md`.
- **`dev/guardrails/record_review.sh pass|block`** writes `.git/gallformers-review/<git write-tree>.md` with the reviewer's report and verdict.
- **`.claude/hooks/require_review.sh`:**
  - A PreToolUse hook on Bash, registered in `.claude/settings.json`.
  - It blocks (exit 2) a command containing `git commit` unless the staged tree's file exists with `verdict: pass`.
  - Merges are allowed (`.git/MERGE_HEAD` present).
  - Restaging after a fix changes the tree, so the fixed diff is reviewed again.
- **Commit routine:** stage by name, run the packet script, spawn `reuse-reviewer` on the packet, fix and restage until it passes, commit.
- **Disputes:** an author who disputes a block asks Jeff, and doesn't re-run the reviewer for a different answer.
- **Scope:** only commits made through Claude Code are gated.
- Cost: one Sonnet run per commit.
- Proof: a test of the hook script with a staged change and no review (blocked), with a passing review (allowed), and during a merge (allowed).

### 5. Builder agent and plan lines

- **`.claude/agents/builder.md`:**
  - `model: inherit`. Every agent that writes code in this repo is spawned as `builder`.
  - Standing instructions: search before writing, and call the functions the task names.
  - It does the task's deletions in the same change.
  - Its hand-back lists each new public function, component and module, and why an existing one didn't fit.
- **CLAUDE.md, one line:** each plan task names what it deletes ("Deletes:") and the functions it calls ("Calls:", never "as in X"); code-writing agents are `builder`; one matter per session.

### 6. Session hooks

- **`.claude/hooks/compaction_count.sh`:** a SessionStart hook on `compact`.
  - It counts compactions per session in `.git/gallformers-sessions/<session_id>`.
  - From the second one on, it prints into the new context: "This session has compacted N times. Finish the current task, record where it stands in its matter, and start a fresh session."
- **`.claude/hooks/new_lib_file.sh`:** a PreToolUse hook on Write.
  - The first Write of a file that doesn't yet exist under `lib/` is blocked once, with: "Name the existing modules you checked and why none fits, then write it again." The next attempt at that path passes.
- Proof: tests of both scripts against sample hook input.

### 7. CLAUDE.md stays under 5,000 bytes

`test/gallformers/guardrails/claude_md_test.exs` fails when `CLAUDE.md` is over 5,000 bytes. Raising the limit is Jeff's call. Lands after task 5's line is in.

## Not doing

- **An orphan-page test:** the retirements test covers replaced pages, the audit's case. A link finder over the router turns up about 60 false hits (API, dashboards, auth).
- **New conformance rules** for link-styled buttons and hand-rolled panels: `b230` writes them once it has the cases.
- **A shared test-fixtures module:** task 1 catches copied fixtures. Their cleanup is `b230`.
- **Another clone detector, or a periodic slop audit:** tasks 1, 2 and 4 cover them.
- **Changes to the worktree flow:** the commit gate reviews every commit's diff, whatever the flow.

## Order

1, 3, 2, 7, 4, 5, 6. The cheap build checks go first. The gate goes before the builder and the session hooks, so those land through it.


## Built (2026-11-09, uncommitted)

All seven tasks are built and tested; nothing is committed.

- **1.** `duplicates` config in `.credo.exs`; `Gallformers.Guardrails.DuplicateCode` (`test/support/guardrails/`), its test, and `mix gallformers.guardrails.baseline` (runs in test). Baseline: 24 sets of files, 63 findings.
- **2.** `Gallformers.Credo.Checks.Architecture.SingleEntryPoint` with 11 tests. Configured in `.credo.exs` as the table above. On its first run it caught a stale pending entry: `ItemRow` decides through `Answer` and doesn't call `Import.decide_*` itself (its mentions are docs), so it came off the list. A direct `wcvp_lookup().search` added to `HostRangeLive` was flagged, then reverted.
- **3.** `Gallformers.Guardrails.Retirements`, `test/support/retirements.exs` (empty), 5 tests.
- **4.** `dev/guardrails/review_packet.sh`, `dev/guardrails/record_review.sh`, `.claude/hooks/require_review.sh`, `.claude/agents/reuse-reviewer.md`, 10 tests. The hook is registered and live: a `git commit --dry-run` was blocked. The scripts were written before their test, against the TDD rule; the test came after and caught the packet printing a relative path. The reviewer agent hasn't run on a real packet yet.
- **5.** `.claude/agents/builder.md`; CLAUDE.md's planning line (now 4,874 bytes).
- **6.** `.claude/hooks/compaction_count.sh` and `.claude/hooks/new_lib_file.sh`, 7 tests. Both registered; the new-file hook is live (a probe Write under `lib/` was blocked). The compaction hook fires only on a real compaction.
- **7.** `test/gallformers/guardrails/claude_md_test.exs`; proven to fail over 5,000 bytes.

**Checks (corrected):** the first report said format was clean; it wasn't (the exit status was read through a pipe), and Jeff had to format three files. Under `mix precommit` the copied-code test also failed every time: `credo --strict` starts Credo's supervisor in the same VM without starting the application, so `DuplicateCode` asserting `{:ok, _} = Application.ensure_all_started(:credo)` failed as already started. Plain `mix test` never showed it. Fixed: an already-running Credo counts as started. `mix precommit` now exits 0 (4,542 tests, 0 failures, exclusions clean). Outside this matter: the dev-env compile fails on a Boundary reference in `dev/gallformers_web/dev/mockups/fact_edit_mock.ex:1000` (committed with cb28; precommit compiles in test).

**Left:** commit. The reviewer's first real run was on the plant-merge work: it blocked `PlantMerges` for copying `TaxonMerges`' load, parse and chain checks; 6611 Task 10 adds the first retirement entries.

