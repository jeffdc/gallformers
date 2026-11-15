---
plan: taxogall
phase: a627
title: Move the migration's legacy Inducers and Hosts onto the import path
stage: committed
created: "2026-11-15T19:06:35Z"
updated: "2026-11-15T19:06:35Z"
---

3,691 Inducer and 8,265 Host attributions (LegacyFacts.inducers, .hosts). Swap that module's direct asserts for building and submitting packages, with the plan-level comparison check green before and after. Deletes: the module's direct assert calls for this kind. Calls: the package builder, Import.submit_package/3.

Study: /Users/jeff/dev/gallformers/docs/plans/2026-11-12-history-audit/state/6-migration-via-import.md
