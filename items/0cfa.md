---
plan: taxogall
phase: "81e9"
title: Save coordinates when an occurrence is imported
stage: committed
created: "2026-11-15T21:51:13Z"
updated: "2026-11-15T21:51:13Z"
---

Jeff, 2026-11-15: recorded occurrences keep their coordinates, saved at import, whether a Source prints them (e.g. '38.5°N 121.7°W') or an iNaturalist observation carries them (Add from observation, and observation-linked statements). Today the occurrence Fact has no coordinates (the 2026-10-27 deferral is replaced). Add coordinates as written, and parsed where possible, to the contract's occurrence Fact, the producer guide, the validator and the apply code, and have Add from observation keep the observation's coordinates. Failing tests first.

Deletes: nothing. Calls: the occurrence Fact's writer (One write path), Import.Validator.
