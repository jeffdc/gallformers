---
plan: taxogall
epic: db43
title: One name search in GallformersWeb.Choices
state: open
needs:
  - "7378"
docs:
  - .mull/matters/b230-review-cleanup-one-way-to-handle-a-name-we-don-t-have-and-the-2026-11-09-audit.md
created: "2026-11-09T20:38:17Z"
updated: "2026-11-09T20:38:17Z"
---

From matter b230, Task 3. The 2026-11-09 audit adds: include TaxonomyLive.RangeEditor (.credo.exs lists it as pending on b230), and name the Choices functions .credo.exs expects, one for WCVP plants and one for iNat taxa. Clear the b230 pending entries in .credo.exs once the callers use Choices. Sizing is the intake's guess: if it doesn't fit one session, mull ask to split it.
