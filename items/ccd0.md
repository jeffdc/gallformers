---
plan: taxogall
title: An optional proposed descriptor for undescribed Galls in the import contract
stage: captured
kind: idea
category: import
source: matter 86e7; loose end 6aab (migrated)
created: "2026-11-11T13:32:49Z"
updated: "2026-11-12T02:23:22Z"
---

**The idea** (`86e7`, "After the tasks", and its follow-ups): "Contract follow-up (not in this plan): an optional proposed descriptor for undescribed Galls in `294c`."

**Background.** An undescribed Gall's name is "<Genus> <descriptor>", or "Unknown (<Family>) <descriptor>" when the Inducer is above genus, e.g. "Belonocnema q-brandegeei-midrib-gall" (`86e7` §1). The descriptor also seeds the Gallformers code when the Gall is created; after that, name and code are independent. `86e7` §5: "New Galls from imports get their parts from the batch (an undescribed Gall's descriptor from its proposed label)". The contract has no such field yet.

**As of a0434bcf**, `Gallformers.Import.ApplyGall` generates the descriptor itself: the Host's genus initial and epithet, then the Source's `name_as_written`, slugged (lowercase ASCII, hyphenated, at most 60 characters), e.g. "Andricus q-lobata-a-small-spindle-shaped-gall-on-the-leaf-midrib". A name or code already taken is numbered "-2", "-3", …. `priv/import/schema/gall.schema.json` has no descriptor field.

**What it would take.**
- An optional field on a gall-batch Gall in the contract (`priv/import/schema/`, `validate.py`, the Elixir validator, `PRODUCER_GUIDE.md` and `docs/import/producer-guide-background.md`), saying the proposed descriptor and its format (today's convention: `<h>-<host epithet>-<short description>`).
- `ApplyGall` uses it when present, still numbering collisions, and falls back to the generated slug when absent.
- A contract change goes through the contract's own process (`294c`; fixtures, golden runs).

From matter 86e7 ('After the tasks'; Status, follow-ups); loose end 6aab (migrated).
