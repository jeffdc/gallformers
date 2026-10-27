---
status: raw
created: 2026-09-14
updated: 2026-10-27
epic: taxonomy
relates: [803b, a856]
---

# Structured gall name builder

Give every Gall a unique, human-readable name derived from its data (`8567` rule 9). Part of taxogall: `50ff` step 10, `b5bd` M3.

## Rules (from `8567` and `b5bd`)

- **Derived:** the Inducer's name plus only the qualifiers needed for uniqueness, in order: generation, then Host, then form ("a derived name adds a generation, then a host, then a form qualifier as needed", `b5bd`). A generation's qualifier text comes from its generation group (`8567`, *Generation groups*), e.g. "(agamic)"; a Host qualifier reads e.g. "(on Pyrus)".
- **Overridable:** a Gall can carry an editorial name override; today's overrides carry over (`b5bd` M2, editorial carry-over).
- **Unique,** case-folded. Today's names are already unique (production snapshot: zero case-folded duplicates).
- **Renames — decided B (Jeff, 2026-10-27; `8567`):** when a taxon change would change a Gall's derived name, the new name is proposed and a curator reviews it before it takes effect; the old name becomes a gall alias when accepted. The Gallformers code is never changed automatically: it is derived from the name and ties existing iNat observations to the Gall, so a code change is a separate, deliberate curator decision. A collision still goes to a curator.
- **No label-builder screen:** every write is a batch (rule 12); names follow from the data, and overrides arrive like any other write.

## Still to decide

- **Undescribed Galls** with no species-level Inducer: the base, e.g. genus or family plus Host plus a short descriptive phrase, as today's undescribed names do.
- **Migration:** every current name survives. Known suffix patterns map to derived names (`b5bd` *Name-suffix categorization*: ~900 mechanical, 47 curated); the rest become overrides.
- A Gall's name carries no authorship and no taxonomic synonyms; a Gall's common names are `alias` Facts.

History: extracted from the dropped `2cb2` draft (a label-builder UI with recipes, primary inducers and confidence), which `8567` superseded.
