---
status: refined
created: 2026-05-02
updated: 2026-05-03
epic: ingestion
---

# Extract Ingestions context module into focused sub-modules

## Problem

`lib/gallformers/ingestions.ex` is too large and mixes several concerns that should not live together long-term:
- submission and duplicate gating
- ingestion lifecycle orchestration
- pipeline-facing extraction persistence
- source-association workflow
- admin-screen presentation shaping
- species-review workspace assembly

That makes navigation and testing harder than necessary.

This refactor is no longer purely mechanical.

Matter `97c4` now gives a much clearer product model for the ingestion flow. The review unit is species, not extracted mention rows. The flow is split into an `Ingestion Overview` and a separate `Species Review Workspace`. New source creation should use the existing source screen with an ingestion-aware return path. The species workspace should be master-detail, identity-first, and closer to the Gall Admin interaction model.

If this matter proceeds by extracting the current row-centric review implementation into clean sub-modules as originally proposed, it will harden the wrong abstraction and make the transition to the agreed workflow harder.

So the problem is now twofold:
- `Gallformers.Ingestions` needs decomposition
- that decomposition must support the agreed product boundaries from `97c4` rather than reinforcing the current row-centric workspace

## Relationship To 97c4

This matter is explicitly subordinate to `97c4`.

`97c4` now establishes these concrete product boundaries:
- duplicate handling is an early gate before expensive processing
- automated processing runs without user intervention until review is ready
- post-processing lands on an `Ingestion Overview` screen for triage
- source attachment is the gate out of the overview
- existing-source matching stays inline in the overview
- new-source creation uses the normal Source screen with preloaded ingestion data and returns to the overview after save
- species review happens in a separate master-detail workspace
- the species detail pane is identity-first and only fully populates aliases, hosts, and traits after gall mapping is resolved

This matter should support that architecture by reducing context sprawl and moving obvious non-domain code out of `Gallformers.Ingestions`, but it should not prematurely freeze the deeper review-domain boundaries before the implementation shape is clearer.

## Revised Goal

Refactor `Gallformers.Ingestions` incrementally in ways that are safe given the now-agreed workflow in `97c4`.

The goal is not to complete the originally proposed module split as written. The goal is to extract the parts that are already clearly separable, while intentionally deferring the parts whose final boundaries depend on the species-centric implementation.

## Safe Early Extractions

These extractions are good candidates before the full species-centric workspace is implemented.

### 1. Admin presenter extraction
Move LiveView-facing labels, queue rows, overview maps, workspace view models, and other UI-shaped data builders out of `Gallformers.Ingestions` into presenter modules near the ingestion review LiveViews.

This is still the highest-confidence extraction because it addresses a real layering problem without forcing a final decision on domain persistence boundaries.

This should include UI-facing shaping for:
- queue and detail status labels
- ingestion overview sections and source-action state
- duplicate-candidate evidence presentation
- species master-list row presentation
- species detail-pane view models and display formatting

The presenter layer may still call into `Gallformers.Ingestions` for domain data and workflow predicates.

### 2. Small pure helper extraction
Extract only the small normalization/access helpers that are genuinely generic and shared.

Keep this narrow and boring. It is not a place to hide workflow logic, review predicates, query helpers, or transaction behavior.

### 3. Submission extraction
Submission flow remains a good self-contained extraction target:
- validate attrs
- create submission record
- upload submission artifact
- run early duplicate gate / enqueue the next step

This workflow is still largely orthogonal to the species-review redesign.

### 4. Lifecycle extraction
Clear/delete/retry behavior is also a reasonable extraction target if it stays focused on ingestion lifecycle operations rather than review semantics.

Retry logic may need to understand pipeline state, but it should not take ownership of the species workspace model.

### 5. Duplicate review extraction
Duplicate-candidate lifecycle may still be extracted, especially now that its role is clearer as a pre-processing gate rather than part of the downstream species workspace.

Any admin-facing evidence shaping should move with the presenter, not with the domain module.

### 6. Source-handoff coordination extraction
The workflow from ingestion overview into source matching or source creation may warrant its own focused extraction once implementation begins.

This is not full source-domain ownership. It is the ingestion-side coordination logic for:
- inline existing-source matching
- preloading data into the normal source screen for new-source creation
- returning to the ingestion overview after save
- attaching the resulting source back to the ingestion

This boundary is now product-driven enough to acknowledge early, even if the final module name is left open.

## Extractions To Defer

These parts of the original plan should still be deferred.

### 1. `SpeciesEntries`
The current proposal assumes `SourceIngestionSpecies` rows are a stable domain boundary and a natural module seam.

That may still be true for pipeline persistence, but `97c4` makes clear that these rows are not the user-facing review unit. They may ultimately be only extracted evidence inputs for a species-level review object or grouped workspace.

Until implementation clarifies their role, this matter should not elevate the current row model into a first-class architectural boundary.

### 2. `SpeciesReview`
The original proposal assumes the current per-row workspace is the right unit to modularize.

That assumption is no longer acceptable. The agreed species workspace now implies:
- grouped species-level review loading
- a master-detail navigation model
- identity-first gating before aliases/hosts/traits populate
- existing-vs-new review modes after mapping
- evidence snippets plus a full-text side panel with fragment linking

Those behaviors may require a very different internal split than the originally proposed `SpeciesReview` module.

### 3. Caller migration tied to current review semantics
Do not spend time migrating callers to a direct row-centric review API if that API is likely to change once the species-centric workspace is implemented.

## Revised Early Target Architecture

The early target architecture should be treated as intentionally partial.

```
lib/gallformers/ingestions.ex                                      (stable facade + core ingestion API)
lib/gallformers/ingestions/helpers.ex                              (small pure/shared helpers only)
lib/gallformers/ingestions/submission.ex                           (submission workflow)
lib/gallformers/ingestions/lifecycle.ex                            (clear, delete, retry, abandonment)
lib/gallformers/ingestions/duplicate_review.ex                     (duplicate-candidate lifecycle)
lib/gallformers/ingestions/source_handoff.ex                       (optional: source-attachment flow coordination)
lib/gallformers_web/live/admin/ingestion_review_live/presenter.ex  (overview/workspace view models and labels)
```

Anything specifically about grouped species review, species deltas, or final review persistence boundaries should be revisited after implementation planning begins.

## Sequencing

Recommended order:

1. Keep `97c4` as the product driver
2. Extract presenter logic from `Gallformers.Ingestions`, starting with queue/detail/overview shaping
3. Extract small pure helpers
4. Extract submission
5. Extract lifecycle
6. Extract duplicate review if still useful and clearly bounded
7. Extract source-handoff coordination if that flow starts to sprawl
8. Revisit this matter once the species-centric workspace implementation is being planned
9. Only then decide whether `SourceIngestionSpecies` remains the right domain boundary or whether a different species-review split is needed

## Design Guardrails

- Do not create new sub-modules that imply the current row-centric review model is the long-term design unless that has been explicitly revalidated
- Do not move LiveView-facing formatting into domain modules
- Keep `Gallformers.Ingestions` as the stable facade during incremental extraction
- Preserve public function signatures unless a later product-driven redesign makes a change necessary
- Treat `SourceIngestionSpecies` as an implementation detail under evaluation, not yet as the final review abstraction
- Respect the new product split between ingestion overview, source handoff, and species workspace rather than collapsing them back into one generalized review module

## Success Criteria

This matter is successful if:
- `Gallformers.Ingestions` is smaller and better layered in the clearly safe areas
- admin presentation logic is no longer mixed into the ingestion domain context
- duplicate gating, submission, lifecycle, and source-handoff concerns are easier to navigate and test
- the codebase is better prepared for the species-centric review work in `97c4`
- we avoid spending refactor effort reinforcing a review model that the product is replacing

## Follow-up

Once `97c4` moves from product design into implementation planning, revisit this matter and either:
- expand it with a species-centric module plan that matches the real workspace behavior, or
- split the deferred review-domain refactor into one or more follow-up matters with boundaries that match the implemented workflow.
