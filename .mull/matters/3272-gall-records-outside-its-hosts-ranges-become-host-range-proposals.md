---
status: raw
created: 2026-10-26
updated: 2026-10-26
epic: taxonomy
relates: [50ff]
---

# Gall records outside its Hosts' ranges become Host-range proposals

A Gall's range can never extend beyond the union of its Hosts' ranges (native and introduced). Jeff (2026-10-26): "we should never allow a gall to have a range that falls outside of ALL hosts it is attached to. it seems to me that this is a statement of the hosts range, even if introduced. we need to add a feature for this at some point."

So when a Source (or Gallformers) records a Gall in a place where none of its Hosts grows, that is evidence about a Host's range — usually the Host is introduced or planted there, or the Host's range data is incomplete — not a widening of the Gall's range.

## What exists (taxogall phase 1)

- The `include` range adjustment is removed: a Gall's range = its Hosts' union, minus exclusions, optionally restricted by `only` (`8567` rule 10).
- Such a place is stated as a recorded occurrence (`occurrence` Fact: place, when, stage, evidence), which the import contract already carries (`294c`).
- Today's stored gall ranges become no Facts (`b5bd` M0, option A); past cases where a curator widened a gall's range instead of its Host's are fixed on the Host, editorially (`8567` rule 1), after release.

## The feature (later)

- Find recorded occurrences that fall outside every Host's range (native and introduced) and propose a Host-range change for a curator: which Host, which place, native or introduced, with the occurrence's evidence.
- Accepting it changes the Host's range (editorial, audited); the Gall's range follows.
- Open: where the proposals appear (the admin queue, `e381`, or a range-curation screen); whether a proposal can also come from an Observation (a Research Grade iNat record) rather than a Source.
