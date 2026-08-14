---
status: done
created: 2026-04-25
updated: 2026-04-28
epic: source-ingestion
relates: [fe8c]
---

# Storage and module reorg follow-up for source artifact publishing

## Goal

Refactor storage-related code so Gallformers domain modules do not know about S3 details directly.

Target boundary:
- `Gallformers.Storage` is the storage-layer umbrella.
- `Gallformers.Storage.S3` is the only ExAws/S3-facing adapter.
- `Gallformers.Storage.Images`, `Gallformers.Storage.PDFKeys`, and `Gallformers.Storage.SourceArtifacts` own storage-specific naming, bucket selection, object operations, and URL helpers for their slice.
- higher-level Gallformers domains call those storage modules rather than constructing S3 keys, choosing buckets, or dealing with raw S3 semantics themselves.

This should be done incrementally. Each phase should move one boundary decisively forward without requiring the entire storage stack to be rewritten in one pass.

## Target module shape

### `Gallformers.Storage`
Storage-layer umbrella namespace.

Responsibilities:
- namespace root only
- possibly temporary compatibility delegators during migration
- no long-term concentration of image-specific or source-specific logic

### `Gallformers.Storage.S3`
Lowest-level S3 adapter.

Responsibilities:
- wrap ExAws calls
- preserve test-safety behavior that currently prevents accidental AWS calls in test
- provide a stable seam for possible future dependency injection

Non-goal for now:
- do not replace this immediately with broad behaviour injection everywhere unless the migration clearly becomes simpler that way

### `Gallformers.Storage.Images`
Storage implementation for image objects.

Responsibilities:
- image object path/key naming where storage-specific
- object upload/delete/list helpers for image storage
- CDN/storage URL helpers tied to image objects
- low-level derivative object operations if they are truly storage concerns

Important caveat:
- image domain policy should not accumulate here just because files live in S3
- variant policy, lifecycle policy, and domain workflow should be reviewed carefully and pushed upward into `Gallformers.Images` / `Gallformers.ContentImages` where appropriate

### `Gallformers.Storage.PDFKeys`
Storage implementation for key PDF artifacts.

Responsibilities:
- canonical key PDF object naming
- upload/delete/url helpers for key PDFs
- any listing or existence checks specifically related to stored key PDFs

### `Gallformers.Storage.SourceArtifacts`
Storage implementation for source-ingestion and source-publication artifacts.

Responsibilities:
- private/public source bucket config
- canonical source-ingestion artifact prefixes and paths
- stage/file path construction for stored source artifacts
- download/list/delete/copy/promote operations for source artifacts
- published source artifact URLs
- storage-specific public publishing mechanics

Important caveat:
- storage ownership here includes public artifact promotion and naming
- cross-domain publication orchestration should still be evaluated separately from low-level storage mechanics

## Refactor principles

- Move path naming to the storage module that owns the artifacts.
- Move bucket selection to the storage module that owns the artifacts.
- Keep ExAws access behind a single adapter layer.
- Avoid one-shot rewrites; each phase should leave the codebase in a coherent intermediate state.
- Use compatibility delegators when they make the migration smaller and safer.
- Prefer moving responsibilities to their final owner before renaming public APIs broadly.
- Preserve behavior during early phases; boundary cleanup comes before feature changes.

## Phase 1: Establish `Gallformers.Storage.S3` as the single S3 adapter

*DONE*

### Objective
Create a clear storage-internal adapter boundary so all storage implementations use the same S3 access layer and no higher-level domain code needs to know about ExAws.

### Work
1. Introduce or rename the existing S3 wrapper to `Gallformers.Storage.S3`.
2. Update storage-facing modules to use `Gallformers.Storage.S3` rather than a top-level `Gallformers.S3`.
3. Audit for direct `ExAws` usage in Gallformers runtime code and route storage usage through the adapter.
4. Decide which direct `ExAws` callers are genuinely storage concerns versus standalone tooling.
5. Keep the current test-isolation behavior unless there is a compelling reason to change it during this phase.
6. Add or update tests proving that storage modules continue to avoid real AWS calls in test.

### Expected result
- one clearly defined S3 adapter module under `Gallformers.Storage`
- storage modules depend on that adapter, not directly on ExAws
- no functional behavior change beyond namespace cleanup and consistency

### Things explicitly out of scope
- broad dependency-injection redesign
- moving image/key/source responsibilities yet
- changing path rules or bucket layout

## Phase 2: Extract key PDF storage into `Gallformers.Storage.PDFKeys`

*DONE*

### Objective
Remove key-PDF object naming and upload concerns from the `Keys` domain so key storage becomes a first-class storage slice.

### Work
1. Create `Gallformers.Storage.PDFKeys`.
2. Move canonical key PDF object-path construction out of `Gallformers.Keys`.
3. Move key-PDF URL construction out of `Gallformers.Keys`.
4. Move upload-oriented helpers used by `Keys.PdfGenerator` into `Storage.PDFKeys` where appropriate.
5. Decide whether delete/list/existence helpers are needed immediately or should be added only when existing callers require them.
6. Update `Keys` and `Keys.PdfGenerator` to depend on `Storage.PDFKeys` rather than shared generic storage primitives plus domain-owned path naming.
7. Preserve the current external behavior and URLs.

### Design intent
After this phase, `Keys` should decide that a PDF must exist, but not how its object key is structured in S3.

### Expected result
- key PDF storage logic has a home
- `Keys` stops owning S3-ish path semantics for PDFs
- `Gallformers.Storage` becomes less of a generic dumping ground

### Things explicitly out of scope
- image refactor
- source artifact refactor
- changing how Typst generation itself works

## Phase 3: Consolidate source artifact storage under `Gallformers.Storage.SourceArtifacts`

*DONE*

### Objective
Move canonical source artifact path ownership into storage so ingestion/source code stops constructing or owning S3 path rules for source artifacts.

### Work
1. Expand `Gallformers.Storage.SourceArtifacts` so it owns canonical private artifact prefixes and file paths for source ingestions.
2. Move `source-ingestions/{id}` prefix construction out of `Gallformers.Ingestions`.
3. Move helpers equivalent to `artifacts_path_for/1` and `artifact_path/2` into source-artifact storage-owned code.
4. Decide the internal shape:
   - keep paths directly in `Storage.SourceArtifacts`, or
   - introduce a focused helper such as `Storage.SourceArtifacts.Paths`
5. Update `Gallformers.IngestionPipeline.Storage` to call the storage-owned path API.
6. Update source publication code to resolve assembled markdown paths through `Storage.SourceArtifacts`, not `Ingestions`.
7. Review whether stage/file layout helpers belong in `IngestionPipeline.Storage` or should be pushed down further into `Storage.SourceArtifacts`.
8. Preserve persisted `artifacts_path` behavior where needed during migration, even if path ownership moves.

### Design intent
`Ingestions` may still persist an `artifacts_path` field, but it should not be the long-term owner of storage path semantics.

### Expected result
- all source artifact naming rules live with source artifact storage
- `Ingestions` becomes less coupled to S3 path structure
- publication and pipeline code stop depending on ingestion-domain path helpers

### Things explicitly out of scope
- publication orchestration redesign beyond what is needed to adopt the new path API
- image policy cleanup

## Phase 4: Extract `Gallformers.Storage.Images` and separate image storage from image policy

*DONE*

### Objective
Split the current mixed image-related code into a storage implementation layer plus domain policy, rather than moving the entire current `Storage` module wholesale into a new namespace.

### Work
1. Create `Gallformers.Storage.Images`.
2. Move image-specific object naming, object deletion, object listing, and related storage helpers out of `Gallformers.Storage`.
3. Inventory all current image-related functions and classify each one as either:
   - storage implementation concern
   - image-domain policy concern
   - temporary compatibility wrapper
4. Move only true storage concerns into `Storage.Images` first.
5. Review size variant generation carefully:
   - low-level derivative upload mechanics may belong in storage
   - policy about which variants exist, when they are generated, and for which domain objects likely belongs in `Images` / `ContentImages`
6. Review article image helpers and gall image audit helpers to determine whether they are storage-owned listing concerns or should be split further.
7. Update callers incrementally from `Gallformers.Storage` to `Gallformers.Storage.Images`.
8. Leave delegators in `Gallformers.Storage` temporarily where this reduces migration churn.

### Design intent
This phase is not just a file move. It is the point where image code should be rethought so storage code stops carrying image-domain workflow decisions by accident.

### Expected result
- a dedicated image storage module exists
- image storage operations are separated from image lifecycle policy
- the top-level `Storage` module becomes thinner and more coherent

### Things explicitly out of scope
- redesigning the image domain data model
- changing user-visible image behavior unless required to preserve consistency during the extraction

## Phase 5: Reposition `Gallformers.IngestionPipeline.Storage` as a pipeline-facing facade

*DONE* - as part of Phase 3

### Objective
Clarify what remains pipeline-specific after source-artifact storage owns the underlying storage rules.

### Work
1. Review `Gallformers.IngestionPipeline.Storage` after Phase 3.
2. Keep only the APIs that are genuinely pipeline-facing conveniences.
3. Push low-level bucket/path/object logic down into `Storage.SourceArtifacts`.
4. Decide whether `IngestionPipeline.Storage` should continue to expose stage-aware CRUD helpers or whether callers should use `Storage.SourceArtifacts` directly.
5. Reduce duplication between pipeline storage helpers and source publication helpers.
6. Ensure the remaining facade is intentionally small and readable.

### Design intent
This module should exist only if it provides useful pipeline vocabulary. It should not duplicate storage ownership that belongs below it.

### Expected result
- clearer line between pipeline convenience APIs and underlying storage ownership
- less duplication and less uncertainty about where future source-artifact code belongs

## Phase 6: Re-evaluate publication orchestration boundary

*DONE*

### Objective
After storage ownership is cleaned up, decide what the right home is for publication orchestration that crosses ingestions, sources, and storage.

### Work
1. Revisit the current publication bridge/orchestrator once path and copy logic are fully storage-owned.
2. Decide whether the current module should remain a neutral cross-context orchestrator or be renamed.
3. Keep low-level publication mechanics in `Storage.SourceArtifacts`.
4. Keep any cross-domain workflow steps above the storage layer.
5. Ensure the final API makes the separation obvious:
   - storage module owns where bytes go and how they are copied
   - orchestration module owns when publication happens and which domain entities participate

### Expected result
- publication code has a stable boundary after the lower-level refactor settles
- no premature movement of orchestration into the wrong layer

### Things explicitly out of scope
- broad source-domain redesign unrelated to storage/publication boundaries

## Phase 7: Collapse transitional wrappers and finalize boundaries

*DONE*

### Objective
Remove migration scaffolding once callers have moved to the new module layout.

### Work
1. Audit `Gallformers.Storage` for transitional delegators added during earlier phases.
2. Remove wrappers that no longer provide meaningful compatibility value.
3. Tighten module docs to reflect final ownership boundaries.
4. Update tests to target the final module layout rather than temporary compatibility APIs.
5. Review Boundary declarations and dependencies so the architecture is enforced, not just documented.
6. Do a final pass for direct bucket/path/S3 leakage back into domain modules.

### Expected result
- the module layout matches the intended architecture rather than preserving refactor-era shims indefinitely
- future storage work has an obvious destination

## Deliverable expectations per phase

For each phase:
- the codebase should compile and tests for touched areas should pass
- behavior should remain stable unless a phase explicitly calls for a behavior decision
- ownership should be clearer at the end of the phase than at the beginning
- avoid landing partial moves that create two long-term homes for the same responsibility

## Open design questions to resolve during implementation

- Whether `Gallformers.Storage.S3` should remain a simple module wrapper or grow a behaviour-backed adapter interface later.
- Whether source-artifact path helpers belong directly in `Storage.SourceArtifacts` or in a nested `Paths` helper.
- Which parts of image variant generation are truly storage-level mechanics versus image-domain policy.
- Whether `IngestionPipeline.Storage` remains valuable as a thin facade once source-artifact storage is fully built out.
- Whether the publication orchestrator should keep its current name or adopt a clearer neutral namespace after lower-level responsibilities settle.

## Non-goals

- one-shot rewrite of all storage code in a single PR
- immediate replacement of the S3 wrapper with full dependency injection everywhere
- merging image, PDF, and source artifact logic into a single generic storage abstraction
- letting higher-level domains continue to own S3 bucket/path semantics after the refactor is complete


## Phase 1 note: presigned URL encapsulation

- `Gallformers.Storage.S3` now owns presigning as well as `request/1`, so `Gallformers.Storage.presigned_upload_url/2` is only responsible for image-specific inputs like bucket, path, expiry, and content type.
- In test mode (`s3_enabled: false`), the adapter returns a deterministic mock presigned URL instead of invoking ExAws presign logic. This keeps presigning under the same test-isolation rule as request execution and avoids leaking AWS config/credential assumptions back into callers.
- This keeps the Phase 1 boundary coherent: storage-facing modules can depend on `Gallformers.Storage.S3` for all raw S3 mechanics, not just request dispatch.
