---
status: refined
effort: 5-7 days
created: 2026-02-16
updated: 2026-08-12
epic: taxonomy
relates: [ede2, 3e8c]
blocks: [f49a]
docket: true
---

# Species merge and split operations

Taxonomic merges (synonymization) and splits are frequent operations that need to be easy and safe. Primarily about galls but should not exclude plants. Key challenge: handling all the associated data (traits, hosts, images, sources, aliases) correctly during these operations.

Interview with Adam on 2026-02-22 validated the core gall-side model and exposed additional requirements for host taxonomy, iNaturalist mapping, and review workflows.

## Core model

### Merge (synonymization)

Merge is NOT a destructive data-union operation. It's aliasing + redirect. So merging B -> A:

- B stays in the database; its record, traits, hosts, images, and sources stay intact
- B becomes read-only (frozen)
- B's name becomes a scientific synonym alias on A
- B redirects to A on the public site
- B's Gallformers code stays on B so existing references still resolve through the redirect
- Search for B finds A through redirect-aware search/typeahead
- Admin can selectively copy data from B -> A during the merge workflow

Important clarification from Adam: the selective "copy from B to A" flow is not a side feature. In practice the taxonomically valid name is often the sparser record, so the merge UI needs a first-class interface for pulling chosen data from the frozen synonym into the keeper.

Data model changes:
- `merged_into_id` (FK to species, nullable) -> this species is now considered a synonym of X
- Read-only status implied by `merged_into_id` being non-null
- Display/routing layer handles redirect
- Admin layer blocks edits on merged species
- API behavior needs explicit design

### Split (clone + diverge)

Split is a clone operation followed by manual cleanup:

- Admin presses Split on species A
- All details of A are copied into new species B (traits, hosts, images, sources, etc.)
- Admin renames B to something unique
- A new alias is added to B pointing back to A (its former name)
- Admin then edits both A and B to trim/adjust what doesn't apply to each

Adam confirmed this works for gall splits. Revision papers generally make it clear enough which traits and hosts belong to each resulting species, even if Gallformers-specific ecological data still needs manual cleanup.

## Data surface

All FKs pointing at `species.id` that merge/split must account for:
- `gall_traits` (1:1, includes `gallformers_code`, `undescribed`, `detachable`)
- 9 M:M trait tables (`gall_color`, `gall_walls`, `gall_cells`, `gall_shape`, `gall_texture`, `gall_alignment`, `gall_plant_part`, `gall_form`, `gall_season`)
- `gallhost` (gall-host relationships)
- `image` (photos)
- `species_source` (citations)
- `alias_species` (alternative names)
- `species_taxonomy` (family/genus/section links)
- `host_range` (plant geographic range)
- `gall_range_exclusion` (gall range exclusions)
- `abundance` (species-level field)

## Validated decisions from Adam

### Gall merges are well-served by the non-destructive model

The "freeze B, redirect to A, keep B intact" model maps cleanly onto gall synonymization. The valid name may not be the richer record, so preserving the synonym's data is essential.

### Gall splits are well-served by clone + diverge

The proposed split workflow is realistic for galls. It does not need a complex allocation wizard.

### Unmerge should be supported from the start

Taxonomic reversals happen. Because the merge is non-destructive, unmerge is mostly: unfreeze B, remove redirect, and optionally clean up anything copied into A.

### Chained merges should be flattened

If B -> A and later A -> C, update B to point directly to C. No redirect chains.

### Rank changes need no separate tool

Gallformers does not currently model subspecific ranks. In practice these changes present as rename or merge/split operations.

### Batch operations matter

Revision papers can trigger many discrete merges and splits in a burst. The system does not need a special compound-operation model, but it does need merge and split workflows that are fast and repeatable.

## Host-side complexity

Adam's strongest feedback was that host taxonomy changes cascade differently than gall taxonomy changes.

### Host plant splits need a triage workflow

When a host plant splits, every gall referencing the old host is affected. The workflow needs to surface the impacted galls and offer at least three distribution modes:

1. Fan out -> apply the gall-host association to all resulting species, flag each as unverified
2. Default substitute -> pick one likely successor species for most galls, flag as unverified
3. Per-gall assignment -> let the admin route affected galls individually

This is not a different data model so much as a more sophisticated UI flow than the gall split path.

### Host plant merges need review of affected galls

A host merge is simpler than a host split because there is only one target, but it still should not silently repoint every gall-host association. The UI should show affected galls and make the repointing visible/reviewable.

### Inherited/unverified marker on gall-host associations

When host-split workflows create successor associations automatically, those new associations should carry an inherited/unverified flag so they can be found and corrected over time.

Open question: whether this marker is purely internal/admin-only or also visible publicly.

### Host taxonomy override flag

Gallformers sometimes intentionally diverges from POWO or iNaturalist on host taxonomy. Host records need a taxonomy override/exemption flag so future automated syncs do not overwrite deliberate editorial decisions.

## iNaturalist implications

### First-class iNaturalist taxon ID mapping

Gallformers species records should carry a direct mapping to iNaturalist taxon IDs. This is important in its own right and becomes more important when taxonomy changes on either side.

### iNat mismatch detection and task queue

When a Gallformers merge or split breaks the correspondence with iNaturalist taxonomy, the system should:
- detect the mismatch automatically
- record the old-name -> new-name mapping
- surface it as a task/queue item so the iNat-side cleanup work is tracked

The actual iNaturalist work remains human-driven, but the system should make sure the mismatch does not disappear into memory.

## Design decisions

### Display: A shows A's data only

A's page shows A's own data. B is NOT unioned into A at query time. Instead, A should have a taxonomic history section that shows that B was synonymized into this species, with a link to B.

This implies tracking merges and splits more formally -> likely a separate table such as `species_history` or `taxonomic_events`, not just `merged_into_id` + aliases.

### Split: S3 images

Copy the S3 files during split so each species owns its images independently. Admin can then delete irrelevant ones from either side. Likely present this as an option during the split workflow.

### Split: unique constraints

Copy values as-is during clone, then alert the admin that Gallformers code and name must be changed to be unique before saving. Validation prevents saving until resolved.

### Merge direction is about taxonomy, not data volume

The UI should make it explicit that merge direction is determined by which name is taxonomically valid, not which record has more data. Because the model is non-destructive, the richer record can safely become the frozen synonym.

### Formal history tracking

Merges and splits should be recorded in a dedicated table, capturing:
- event type (merge/split)
- source species
- target species
- admin who performed it
- timestamp
- notes

This feeds the taxonomic history section on species pages and supports auditability.

## What this matter now includes

- Gall merge workflow
- Gall split workflow
- Unmerge support
- Host merge review workflow
- Host split triage workflow
- Taxonomic history/event tracking
- Inherited/unverified marker for propagated host associations
- Host taxonomy override/exemption marker
- iNaturalist taxon ID mapping
- iNat mismatch queue/task tracking

## Sequencing thought

This matter is now clearly larger than a single simple feature. It may need to split into follow-up implementation matters, especially if host-side operations and iNat mismatch tracking would otherwise delay the core gall merge/split workflow.
