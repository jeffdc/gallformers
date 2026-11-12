---
plan: taxogall
phase: db43
title: 'Review tests: shared fixtures, and the causes of the ''client exited'' errors'
stage: committed
docs:
  - .mull/matters/b230-review-cleanup-one-way-to-handle-a-name-we-don-t-have-and-the-2026-11-09-audit.md
created: "2026-11-09T20:38:17Z"
updated: "2026-11-12T02:23:22Z"
---

**What:** two test cleanups from the 2026-11-09 audit (finding H). First, move the copied test fixtures and helpers into the shared support modules and delete the copies. Second, find the cause of each "Postgrex … client exited" error in the test log and fix it, so `mix precommit`'s log is free of them. This is b230's Task 9. It's small and can go in any order after item f926 (retiring `ItemRow`). References are as of `65531d59`.

**1. Copied fixtures.** Move them into `Gallformers.ImportFixtures` (`test/support/import_fixtures.ex`), `Gallformers.INaturalistFixtures` (`test/support/inat_fixtures.ex`) and `GallformersWeb.AdminLiveHelpers` (`test/support/admin_live_helpers.ex`), and delete the copies:
- `test/gallformers_web/live/admin/review_live/question_card_test.exs` lines 1-89 copy `galls_step_test.exs` lines 1-91 (same directory).
- `review_live/review_test.exs` lines 77-161 copy `review_live/trait_terms_test.exs` lines 38-118.
- `rubus_tree` is written five times:
  - `test/gallformers/import/inat_taxa_plan_test.exs:24`
  - `test/gallformers/import/inat_taxa_write_test.exs:47`
  - `test/gallformers_web/components/inat_taxon_panel_test.exs:32`
  - `test/gallformers_web/live/admin/review_live/inat_test.exs:54`
  - `test/gallformers_web/live/admin/taxonomy_live/inat_test.exs:30-31`
- About ten hand copies of `open_row`/`choose`/`visible_text` in the review LiveView tests.

`galls_step_test.exs` and the LiveView `trait_terms_test.exs` are step-page tests that item a81c deletes once their decision flows are ported. If that has landed, the copies in `question_card_test.exs` and `review_test.exs` are the only ones left, and they still move to the shared modules.

The duplicate-code check (c800, `test/gallformers/guardrails/duplicate_code_test.exs`) is what catches copied fixtures. c800 left their cleanup to this task instead of adding a new shared-fixtures module. After the move, lower the baseline (`test/support/duplicate_code_baseline.json`) with `mix gallformers.guardrails.baseline`, which runs in test. A baseline is never raised.

**2. The "client exited" noise.** The audit traced these causes:
- In the review: from the dry run (`ReviewLive.Review`'s `preview`/`dry_run`, review.ex about 333-341) and the Host WCVP read (`ReviewLive.Answer` about 280-295). Both run in `start_async`, and the tests don't `render_async`.
- Also in `test/gallformers_web/live/gall_live_edit_test.exs` (about L147-218, L368) and `gall_live_observation_test.exs` (about L174). These are likely from TrayLive's `{:change_set, _}` refresh (`tray_live.ex` about 131). Not pinned down.

Find each cause with the `systematic-debugging` skill, and fix it. Either the test waits on the async work (`render_async`), or the work is stopped at test exit. The project rule applies: noise or a test that fails only sometimes has a cause (timing, data, async race). Find it rather than re-running until clean, and don't hide the log line.

**Calls:** `Gallformers.ImportFixtures`, `Gallformers.INaturalistFixtures`, `GallformersWeb.AdminLiveHelpers`, `Phoenix.LiveViewTest.render_async/2`.
**Deletes:** the copied fixture blocks, the five `rubus_tree` copies, and the hand copies of `open_row`/`choose`/`visible_text`.

**Done when:** each fixture and helper above has one definition in `test/support/`, and the copies are gone. The duplicate-code baseline is lowered. `mix precommit`'s log has no "Postgrex … client exited" lines.

precommit's log still shows Postgrex 'client exited' errors (seen at intake, 2026-11-09).

From matter b230, Task 9 (finding H). Sizing is the intake's guess: if it doesn't fit one session, mull ask to split it.

Before Model v2 this item needed f926. Items have no needs now; order work with needs between phases.
