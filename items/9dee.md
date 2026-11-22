---
plan: taxogall
phase: d51b
rank: 100
title: Rebuild dev from a current production copy and run the migration strict
stage: committed
created: "2026-11-15T19:13:52Z"
updated: "2026-11-22T02:26:29Z"
---

Dev's data comes from a production copy of about 2026-10-23, and the two plant merges added to plant_merges.csv on 2026-11-09 (Silphium, Horkelia) were done by hand on dev and have never gone through a migration run. Take a fresh copy (make download-db, make experiment-db), run mix gallformers.catalog.migrate strict, and confirm the merges apply from the file. Report what's pending or new. Before replacing gallformers_taxogall, say so to Jeff (it holds the test data).

Deletes: the dev database's contents, only on Jeff's word. Calls: the Makefile targets and mix gallformers.catalog.migrate.
