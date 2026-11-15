---
plan: taxogall
phase: f709
title: Back up preview's database while it holds decisions not yet exported
stage: committed
created: "2026-11-15T21:23:22Z"
updated: "2026-11-15T21:23:22Z"
---

Preview's database holds curators' real decisions for weeks before cutover, and only its replay log carries them to production. The phase doc lists its backup as not settled. Decide with Jeff how often and where (for example the same full-backup workflow production uses, into its own prefix), set it up, and test a restore onto a scratch database. Jeff runs the Fly and secret commands.

Deletes: nothing. Calls: none.
