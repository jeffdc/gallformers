---
plan: taxogall
phase: "81e9"
rank: 30
title: Rebuild the golden reference answers in format 4
stage: committed
from: d9f6
created: "2026-11-15T21:16:07Z"
updated: "2026-11-22T02:26:29Z"
---

The golden regression set (services/import-producer/golden/) holds Jeff's verdicts from the five trial check pages (177 statements, 18 name matches) taken from format 3 packages. Rebuild them in format 4 from reviewed packages, with Jeff saying which reviews count as reference, so that runs and cost levers can be judged by golden score. Fix the scorer's name matching so it doesn't read the old tables (it breaks at cutover) as part of this or the separate item.

Deletes: the format 3 reference files once replaced. Calls: produce golden score.
