---
plan: taxogall
phase: a627
title: A package builder that turns the migration's plans into Gallformers legacy data packages
stage: committed
created: "2026-11-15T19:06:35Z"
updated: "2026-11-15T19:06:35Z"
---

Turn each migration module's existing plan into packages of about 50 Galls (about 80 gall packages, about 15 taxonomy packages of ~500 acts), extending Import.GallformersFragment (galls_batch/2) rather than copying it. Galls named by their skeleton ids; taxa declared by accepted name, rank and gallformers_taxon_id. A strict run treats any open queue item as a failure.

Deletes: nothing yet. Calls: Import.GallformersFragment, Catalog.gall_summary/1.

Study: /Users/jeff/dev/gallformers/docs/plans/2026-11-12-history-audit/state/6-migration-via-import.md
