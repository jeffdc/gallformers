# Species Merge & Split — PM Interview Summary

**Date:** 2026-02-22
**Interviewee:** Adam (domain expert, Gallformers cofounder)
**Design doc reviewed:** `5c56-species-merge-and-split-operations.md`

---

## 1. Scenarios the current design handles well

### Standard gall merge (synonymization)
The "freeze B, redirect to A, keep B's data intact" model maps cleanly onto how gall synonymizations work. The non-destructive approach is correct: the taxonomically valid name may not be the record with the most data, so preserving B is essential rather than a nice-to-have.

### Standard gall split (clone + diverge)
Clone-and-trim works for gall splits. Revision papers generally make it clear enough which traits and hosts belong to each resulting species, even if the paper focuses on anatomical characters rather than the ecological data Gallformers tracks. The admin can work through it.

### Unmerge (taxonomic reversal)
The non-destructive merge model provides this nearly for free. Since B is frozen with all its original data, unmerging is just: unfreeze B, remove the redirect, and optionally clean up anything that was copied into A during the merge. No separate snapshot or backup mechanism is needed — the frozen record *is* the snapshot.

### Chained merges
Already addressed in the design doc (flatten chains when they arise). No issues raised.

### Rank changes (subspecies promoted, species demoted, etc.)
Gallformers doesn't currently track subspecific ranks, so rank changes present as either renames or merge/split operations. No separate tooling needed.

### Compound operations from revision papers
Big revision papers can trigger 5-10+ merges and splits in a batch. These arrive in bursts (~20 merges and ~20 splits per year, heterogeneous by year). Each operation is discrete and can be chained sequentially. The design doesn't need a compound operation model — it just needs the individual merge and split workflows to be **fast and repeatable** since they'll often be performed in batches.

---

## 2. Scenarios that reveal gaps or need more thought

### "Copy from B to A" is a core workflow step, not optional
The design doc mentions "admin can optionally copy specific values from B -> A as part of the merge workflow (details TBD)." In practice this will be plausibly common, because the taxonomically valid name (the keeper) is often the sparser record. The merge UI needs a first-class interface for selectively pulling data from the frozen synonym into the keeper — not a side feature buried behind "optionally."

### Host plant splits cascade differently than gall splits
When a gall splits, one admin clones and trims two records. When a host plant splits, every gall referencing that host is affected — potentially dozens of records. The Q. dumosa example is illustrative: an old broadly-defined plant species was split into ~5 regional species, and all gall references to the old name became ambiguous.

The host split workflow needs a triage step with at least three options:
1. **Fan out** — apply the gall-host association to all resulting species, flag each as unverified
2. **Default substitute** — pick one primary successor species for the majority of galls (e.g., most Q. dumosa galls are probably Q. berberidifolia), flag as unverified
3. **Per-gall assignment** — for cases where the admin knows which galls go where

All associations created by this process should carry an **"inherited from split — unverified"** flag so they can be identified and corrected over time.

This isn't a fundamentally different data model — it's the same split operation with an additional UI step that surfaces the affected galls and lets the admin choose how to distribute them. But it does need to be designed explicitly rather than handled ad-hoc.

### Host plant merges need similar cascade handling
When a host plant is merged (synonymized), every gall referencing the old host needs its association repointed. This is simpler than a split (there's only one target), but the tool should still surface the list of affected galls for admin review rather than silently repointing everything — especially because Gallformers sometimes intentionally diverges from accepted plant taxonomy.

### Host taxonomy overrides
Gallformers sometimes disagrees with POWO or iNaturalist on host plant taxonomy (users/experts believe a different circumscription is more useful). When automated data pulls from POWO/iNat are implemented, there needs to be a way to **flag a host name as intentionally divergent** so that automated syncs don't overwrite curated decisions. This is especially important since host plant taxonomic changes will be more frequent than gall changes (more researchers working on plants, plus planned automation of host data pulls).

### Merge direction is immaterial to the data
The admin needs to be able to merge in either direction without worrying about data loss. The current design supports this (B's data is preserved regardless of which is A and which is B), but the UI should make it clear that the choice of "which merges into which" is about **which name is taxonomically valid**, not about which record has more data. The richer record might end up being the frozen synonym, and that's fine.

---

## 3. New operations or concepts to add to the design

### iNaturalist taxon ID mapping (first-class field)
Gallformers species records should include a direct mapping to iNaturalist taxon IDs. This mapping is described as a primary concern — it unlocks the ability to fetch iNat observations for any gall species via the API. Currently no structured mapping exists in the Gallformers database (one exists in a separate phenology database but should be rebuilt from scratch).

### iNat mismatch detection and task queue
When a merge or split on Gallformers breaks the correspondence with iNaturalist taxonomy, the system should:
1. **Detect the mismatch** automatically (GF name no longer matches iNat taxon)
2. **Flag it** as a human task with the old-name-to-new-name mapping
3. **Surface it in a queue** so nothing falls through the cracks

The actual iNat-side work (re-identifying observations, updating observation fields) is a human task that can't be fully automated by Gallformers, but the system should make sure mismatches are tracked and the mapping information is readily available.

### "Inherited / unverified" flag on gall-host associations
When a host plant split fans out associations to successor species, each new association should carry a flag indicating it was inherited from a split and has not been independently verified. This is a data-quality marker that enables:
- Filtering to find associations that need expert review
- Distinguishing curated data from automatically propagated data
- Gradual cleanup over time as experts weigh in

Whether this flag is visible to end users on the public site or is purely an internal/admin marker is TBD.

### Taxonomy override / exemption flag
A flag on host plant records indicating "this name is intentionally maintained despite differing from POWO/iNat." This exempts the record from automated taxonomy sync operations. Necessary because Gallformers sometimes uses host circumscriptions that differ from the current botanical consensus, and automated updates should not overwrite deliberate curatorial decisions.

### Host-split triage UI
Not a data model concept but a workflow requirement: when splitting a host plant, the admin needs an interface that lists all affected galls and offers fan-out, default-substitute, or per-gall assignment options. This is distinct from the simpler gall split workflow and should be designed as its own flow.

---

## Summary table

| Scenario | Design status |
|---|---|
| Gall merge | Handled well |
| Gall split | Handled well |
| Unmerge | Handled well (falls out of non-destructive model) |
| Chained merges | Handled well (already in doc) |
| Rank changes | Handled (no special tooling needed) |
| Compound operations | Handled (chain discrete operations) |
| Merge data copying (B -> A) | Gap — needs to be a core UI step, not optional |
| Host plant split cascade | Gap — needs triage UI with fan-out / default-sub / per-gall options |
| Host plant merge cascade | Gap — needs to surface affected galls for review |
| Host taxonomy overrides | New concept — exemption flag for intentional divergence |
| iNat taxon ID mapping | New concept — first-class field on species records |
| iNat mismatch detection | New concept — task queue for broken GF-iNat correspondence |
| Inherited/unverified flag | New concept — data-quality marker for split-propagated associations |
