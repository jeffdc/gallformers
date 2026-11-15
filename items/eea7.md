---
plan: taxogall
phase: a627
title: 'Contract additions for the migration base: a Gallformers legacy data Source form, an alias kind, root placements'
stage: committed
created: "2026-11-15T19:06:35Z"
updated: "2026-11-15T19:06:35Z"
---

Three additions, each through the schema (priv/import/schema), validate.py and its tests, the Elixir validator, the apply code and the producer docs:
- a Source form for Gallformers legacy data, undated (today the only undated route is a reading fix of Source 933, which would list every base package as a fix; touches common.schema.json source, SourceStep.match, review_required?, GallMatcher.curated?, the evidence check in checks.ex and Attributions.statement_attrs);
- an optional alias kind on alias_fact (common_name / former_label / code; today apply writes every imported alias as a common name, apply_gall.ex about 524-531);
- a placement_act with no parent, for the 91 root placements (taxonomy.schema.json; apply_taxonomy.ex about 433-438).
Failing tests first.

Deletes: nothing. Calls: Import.Validator, ApplyGall.key_and_extra, ApplyTaxonomy.

Study: /Users/jeff/dev/gallformers/docs/plans/2026-11-12-history-audit/state/6-migration-via-import.md
