---
plan: taxogall
epic: db43
title: 'Review tests: shared fixtures, and the causes of the ''client exited'' errors'
state: open
needs:
  - f926
docs:
  - .mull/matters/b230-review-cleanup-one-way-to-handle-a-name-we-don-t-have-and-the-2026-11-09-audit.md
created: "2026-11-09T20:38:17Z"
updated: "2026-11-09T20:38:17Z"
---

From matter b230, Task 9 (finding H). precommit's log still shows Postgrex 'client exited' errors (seen at intake, 2026-11-09). Sizing is the intake's guess: if it doesn't fit one session, mull ask to split it.
