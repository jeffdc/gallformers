---
status: raw
created: 2026-11-09
updated: 2026-11-09
epic: platform
relates: [6611, cb28, b016]
---

# Guardrails that hold: stop duplicate code and half-finished replacements

## Why this matter exists

Between 2026-11-06 and 2026-11-08 the taxogall review work (matters `6611` and `cb28`) moved faster than our plans and guardrails could hold: 51, 27 and 35 commits on those three days, against at most 21 a day before. The result was duplicate code and replacements left half finished. Jeff and Claude share the blame: we rushed past what the process could sustain.

What went wrong, found by tracing the matters and git history (2026-11-09):

- **The plans wrote the duplication in.** 6611 Task 7 specified "Search…, Add a new plant ↗, Leave out" for a Host with no match, two answers that do the same thing. 6611 kept the old row component "for the Renames page and the old step pages until they go", so two question UIs ran on one back end. The reuse line said "WCVP search as in `TaxonomyLive.New`", which invites a copy rather than naming the function to call. The cb28 plan gave the iNat panel its own find step and turned the card's iNat search on for one page only, which made a second iNat search and a hint that's wrong on other pages.
- **Retiring went last.** 6611 put "retire the old pages" at the end. New features (missed names, the iNat import) were built before it ran, so each had to work in both UIs.
- **Written rules didn't hold.** CLAUDE.md already says "Search Before You Write" and that the most common failure is writing code that already exists. It was broken anyway. Long sessions made it worse: the main session was rebuilt from summaries 4 times between 11-07 and 11-09, so "use the existing X" survived only as a summary line, and agents were briefed from those summaries.
- **Corrections Jeff had to make in that stretch:** Esc in the typeahead (the shared hook already promised it), batch Accept skipping every Trait, two iNat searches in a mockup, a misread instruction, and the review build done without failing tests first.

The full inventory of what needs cleaning up is the slop audit of 2026-11-09 (tracked in its own matter). Use it as the test set here: a guardrail is worth adding if it would have caught some of those cases.

## The principle

Prose rules get read, then traded away under pressure. Checks that fail the build don't. Prefer guardrails that fail `mix precommit` or CI, then ones built into the tools (hooks, agent definitions, plan templates), and only then written guidance. Keep any written guidance short enough to be read in full.

## Guardrails agreed (Jeff, 2026-11-09: add all five)

1. **Credo's duplicate-code check.** `.credo.exs` lists its enabled checks one by one and leaves out `Credo.Check.Design.DuplicatedCode`. Turn it on and tune its `mass_threshold` against the codebase. Decide how to handle what it finds today: fix it, or a baseline that can only shrink, like the design-system conformance test. It catches copied blocks, not "the same mechanic written differently", which is why item 2 exists.
2. **One entry point per capability, enforced.** A custom Credo check (beside the existing ones in `dev/credo/checks/architecture`), or a `mix xref`-based test, that allows each shared capability to be called from one named module only. First candidates: the name searches (Gallformers taxa and Host choices, WCVP, iNaturalist), the review's decide functions (`Import.decide_queue_item/3` and the rest), and taxon creation. A second "name not found" search should then fail precommit instead of turning up in a walkthrough. The allowlist lives in one place and changes only when someone decides to change it.
3. **Replacing means deleting, in the same task.** Every plan task that builds a replacement also deletes what it replaces. No "keep the old one for now". Every reuse names the function to call, never "as in X". Every agent hand-back lists each new public function and why an existing one didn't fit. Work out where this lives so it's actually used: a plan template, a skill, a check on the matter, or a test that lists modules being retired and fails once their replacement has landed.
4. **A fresh review of each diff before commit, by a different model.** A reviewer with no stake in the plan gets the diff and one question first: what in here already exists in the codebase? It reads the code itself, not the author's summary. **The review should run on a different model from the one that wrote the code**, so it doesn't share the author's blind spots. Decide how it's triggered (a skill, a hook, a step in the commit routine), which model, what it reports, and what blocks a commit.
5. **Shorter sessions and a slower pace.** One matter per session, starting fresh rather than compacting again and again. Matters already hold the decisions, so a fresh start loses less than a summary does. Finish and clean up one feature before starting the next. Explore what can make this stick rather than rely on intent, for example a warning when a session has compacted more than N times, or a docket rule that a matter can't start while another of its epic has retirements outstanding.

## Others to explore

Not agreed yet. Bring each back to Jeff with a recommendation.

- **Claude Code hooks** (`.claude/settings.json`). For example, a hook when a new module or component file is created that asks for the existing one it doesn't duplicate, or a Stop hook that runs the cheap checks.
- **Project agent definitions** (`.claude/agents/`) for the reviewer in item 4 and for builders. Each would have its model, tools and standing instructions fixed, so a brief can't drop them.
- **No orphan pages.** A test that every routed LiveView is linked from somewhere, or is listed as deliberately unlinked. The old step and Facts pages lived on unlinked.
- **Wider design-system conformance.** Extend the conformance test to the patterns the audit found: raw link-styled buttons instead of `button variant="link"`, hand-rolled panels, and copy-matching in code.
- **Test fixtures.** A shared fixtures module and a check against copying setup between test files. The audit found one fixture copied five times.
- **A slimmer CLAUDE.md.** Cut it so its rules are read in full, and move detail to linked docs. Measure what it costs in context today.
- **A periodic slop audit**, like the 2026-11-09 one, run on a schedule or at the end of each matter, with its findings filed as matters.
- **Better Elixir clone detection** than Credo's, if any is worth adding. Check before recommending one.
- **The worktree and branch flow:** whether merging taxogall into feature worktrees and fast-forwarding back hides duplication that a PR-style diff review would show.

## How to work this matter

1. **Explore.** Read this matter, CLAUDE.md, CODING_STANDARDS.md, `docs/design-system/README.md`, `.credo.exs`, `dev/credo/checks/`, `mix.exs` (the `precommit` alias), `.claude/settings.json`, and the slop audit's findings. Find out what each guardrail would take, and whether it would have caught the audit's cases (try it on the code as it stands).
2. **Plan.** Write a full plan into this matter: each guardrail, how it's enforced, what it costs to run, the baseline for today's code, and the order to add them. Get Jeff's approval, then `mull plan c800`.
3. **Execute.** Test-first where it's code. Precommit clean. Each guardrail lands with proof it fails on a known bad case.

Constraints: Jeff's global rules apply (no destructive commands without asking, commits only when Jeff says, stage files by name, never push to main). A guardrail must not raise an existing baseline to pass. Don't weaken precommit's speed without saying what it costs.
