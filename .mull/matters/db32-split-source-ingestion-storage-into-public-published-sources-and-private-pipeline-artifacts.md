---
status: done
created: 2026-04-25
updated: 2026-05-01
epic: ingestion
parent: 7fda
---

# Split source-ingestion storage into public published sources and private pipeline artifacts

## Problem

The current bucket policy makes every object in `gallformers-images-us-east-1` publicly readable. That is acceptable for intentionally published assets, but it is the wrong default for source-ingestion uploads and intermediate artifacts such as extracted text, preprocessed text, LLM-clean output, metadata JSON, and structured extraction payloads.

At the same time, a future feature will expose final processed source markdown directly, so we do want a stable public storage location for published source artifacts.

The architectural problem is that source ingestion currently has only one storage surface. We need two distinct ones:
- a private pipeline storage surface for uploads and working artifacts
- a public publication storage surface for intentionally published source outputs

## Design

**Architecture:** Split source-ingestion storage into two explicit object-storage surfaces with different purposes, different path conventions, and different access assumptions.

### Private pipeline storage

Create a new private bucket:
- `gallformers-private`

This bucket is a general-purpose private bucket for the application. It stores:
- uploaded source files such as the original PDF
- extracted text
- preprocessed text
- LLM-clean output
- metadata JSON
- data-extract JSON
- assembled markdown before publication
- any retry/debug/operator artifacts that are useful operationally but are not part of the public product surface
- future private application data that does not belong in the public bucket

**Private path rule:** Keep the current ingestion-centric key format that the code already uses. Do not redesign the working path layout just because the bucket changes.

Canonical private paths remain of the form:
- `source-ingestions/{ingestion_id}/input/source.pdf`
- `source-ingestions/{ingestion_id}/extract/text.txt`
- `source-ingestions/{ingestion_id}/preprocess/text.txt`
- `source-ingestions/{ingestion_id}/llm_clean/text.txt`
- `source-ingestions/{ingestion_id}/metadata/output.json`
- `source-ingestions/{ingestion_id}/data_extract/output.json`
- `source-ingestions/{ingestion_id}/assemble/output.md`

That preserves the current ingestion/provenance model and minimizes churn in the pipeline implementation.

### Public published-source storage

Use the existing public bucket for intentionally published source artifacts.

Public published-source paths should live under:
- `sources/`

The v1 public artifact is only the final markdown.

Canonical public markdown path:
- `sources/{id}/{title}.md`

Where:
- `{id}` is the `Source` ID, not the ingestion ID
- `{title}` is the source title transformed to snake_case and truncated as needed for a reasonable filename

The implementation must support this as a stable public URL shape, but it should not assume markdown is the only public artifact forever. Future derivative artifacts may also need to live under the same public `sources/` namespace.

### Publication rule

Publication should copy the final markdown from private pipeline storage to the public published-source path.

Do not introduce a second normalization pass. The assembled markdown produced by the pipeline is the artifact that should be copied forward unless a later, separate matter establishes a concrete reason to transform it.

### Boundary rule

Do not treat arbitrary ingestion artifacts as public URLs just because they exist in S3.

The storage layer should make it explicit whether an operation is targeting:
- private pipeline artifacts
- public published-source artifacts

The current pattern of a single generic artifact URL helper is too weak for this boundary. The application API should make the public/private distinction legible in names and usage.

## What Is Already Implemented (Refactor, Do Not Recreate)

The following storage and ingestion pieces already exist and should be refactored around the new boundary rather than rewritten from scratch:

- `infra/s3.tf` — existing public images bucket and bucket policy
- `lib/gallformers/storage.ex` — shared S3 bucket/config helpers for the current public bucket
- `lib/gallformers/ingestion_pipeline/storage.ex` — current ingestion artifact upload/download/list/delete/path logic
- `lib/gallformers/ingestions.ex` — ingestion artifact prefix helpers such as `artifacts_path_for/1`
- existing ingestion pipeline stages under `lib/gallformers/ingestion_pipeline/stages/`
- existing ingestion storage tests under `test/gallformers/ingestion_pipeline/storage_test.exs`
- existing full-pipeline coverage under `test/gallformers/ingestion_pipeline/full_pipeline_test.exs`

## Implementation Plan

**Goal:** Move source-ingestion working artifacts to a private bucket while establishing a stable public `sources/` publication path for final source markdown.

---

### Task 1: OpenTofu for the private bucket and lifecycle policy

**Files:**
- Modify: `infra/s3.tf`
- Modify any related IAM/OpenTofu files if the app role policy lives outside `s3.tf`

**Behavior:**
- Create a new private bucket named `gallformers-private`
- Configure it as non-public:
  - block public ACLs
  - ignore public ACLs
  - block public bucket policy
  - restrict public buckets
- Add a lifecycle rule that expires incomplete multipart uploads after 7 days
- Ensure the application IAM role can read, write, list, and delete objects in this bucket
- Do not add broader retention or expiration rules unless a concrete operational need appears during implementation

**Testing / Verification:**
- `tofu plan` shows creation of the new private bucket and no accidental widening of public access
- lifecycle rule targets incomplete multipart uploads only
- IAM policy allows app access to the new bucket

---

### Task 2: Refactor ingestion pipeline storage to target the private bucket

**Files:**
- Modify: `lib/gallformers/ingestion_pipeline/storage.ex`
- Modify: `lib/gallformers/storage.ex` or related config helpers only as needed
- Modify related config in `config/*.exs`
- Modify: `test/gallformers/ingestion_pipeline/storage_test.exs`
- Modify any stage tests that assume the public bucket name

**Behavior:**
- Keep the existing ingestion artifact key format rooted at `source-ingestions/{ingestion_id}/...`
- Change ingestion pipeline artifact operations so they read/write/list/delete against `gallformers-private`, not the public images bucket
- Preserve the current ingestion-centric path semantics and stage artifact filenames
- Do not break test isolation or the mock S3 backend used by the ingestion pipeline tests
- Remove or narrow any helper that implies every ingestion artifact has a public URL

**Testing:**
- Existing ingestion storage tests updated to assert the new private bucket target while preserving current key shapes
- Stage tests still pass with no path-shape regressions
- Full-pipeline tests still verify the expected artifact keys under `source-ingestions/{id}/...`

---

### Task 3: Add a published-source path builder for public markdown

**Files:**
- Create or modify the minimal application module that should own public source artifact path generation
- Add focused tests for public path generation

**Behavior:**
- Add explicit path-generation logic for published source markdown:
  - `sources/{id}/{title}.md`
- Define and test the filename transform rules:
  - base filename comes from the source title
  - convert to snake_case
  - truncate to a reasonable maximum length when needed
  - preserve `.md` as the suffix
- Use the `Source` ID as the stable directory component so title changes do not create identity ambiguity
- Keep this API specific to published-source artifacts rather than overloading ingestion-pipeline helpers

**Testing:**
- Normal titles map to the expected snake_case path
- long titles are truncated deterministically
- punctuation/whitespace normalization behaves predictably
- nil/empty edge cases fail clearly or fall back in a deliberate, documented way

---

### Task 4: Implement publication copy from private assembled markdown to public source markdown

**Files:**
- Modify or create the storage module that should own cross-bucket copy behavior
- Modify the minimal source/publication-facing module that should invoke that copy
- Add focused tests around publication-copy behavior

**Behavior:**
- Implement a concrete operation for publishing source markdown from an existing reviewed source record
- The operation should accept a `Source` record or `source_id` plus the reviewed ingestion context needed to locate the private assembled artifact
- The source of truth for the copy is the private pipeline artifact:
  - `source-ingestions/{ingestion_id}/assemble/output.md` in `gallformers-private`
- The destination is the public published-source path:
  - `sources/{source_id}/{snake_cased_truncated_title}.md` in the existing public bucket
- The operation should perform an object copy when possible rather than downloading and re-uploading through the BEAM with no reason
- Content must be copied byte-for-byte as the published markdown; do not rewrite frontmatter, normalize whitespace, or apply any second pass to the content
- Destination writes should be idempotent: republishing the same source should overwrite the public markdown deterministically at the same path
- The copy operation should return enough information for callers to persist or display the public path/URL if needed later
- Missing private assembled markdown should fail explicitly and clearly
- The implementation should be narrow for v1, where only markdown is published, but the API shape should leave room for additional published source artifacts later

**Testing:**
- Publishing copies from the private assembled-markdown key to the expected public `sources/{id}/{title}.md` key
- The published object content exactly matches the private assembled markdown
- Republishing the same source targets the same public key
- Missing private assembled markdown returns an explicit error
- Title-based filenames are built through the shared public path builder rather than duplicated ad hoc in the copy code

---

### Task 5: Make the application storage API explicit about private artifacts vs public published files

**Files:**
- Modify: `lib/gallformers/ingestion_pipeline/storage.ex`
- Modify any shared storage helper modules whose naming still assumes one bucket or one artifact surface
- Modify focused tests that exercise storage API behavior

**Behavior:**
- Remove ambiguity from the storage API so call sites can tell whether they are dealing with:
  - private ingestion pipeline artifacts
  - public published source files
- Split responsibilities instead of relying on one generic interface to represent both concerns
- Concretely, the codebase should end this matter with obvious homes for:
  - private ingestion artifact path generation
  - private ingestion artifact upload/download/list/delete
  - public published-source path generation
  - public published-source URL generation
  - publication copy from private to public
- Narrow or replace `artifact_url/3` so it no longer suggests that arbitrary pipeline artifacts should be treated as public web URLs
- Ensure the private bucket name is not discovered indirectly through helpers intended for the public images bucket
- Keep public markdown path construction in one place so future public derivative artifacts under `sources/` can reuse the same namespace rules instead of inventing parallel conventions

**Testing / Verification:**
- Storage tests clearly distinguish private-bucket operations from public-path/public-URL operations
- No remaining helper name implies that every ingestion artifact is publicly addressable
- Call sites that need public paths/URLs use the published-source API, not the private ingestion artifact API
- The resulting module boundaries make it obvious how to add future public source artifacts without reopening the private/public split

## Acceptance Criteria

- a new private bucket `gallformers-private` exists for source-ingestion working artifacts
- source-ingestion uploads and intermediate artifacts use the private bucket while keeping their current `source-ingestions/{ingestion_id}/...` key layout
- there is a defined public markdown path format `sources/{id}/{title}.md`
- publication copies final markdown from private pipeline storage to the public `sources/` namespace without a second normalization pass
- the application storage API clearly distinguishes private pipeline artifacts from public published-source artifacts
- the implementation supports v1 markdown publication without preventing future public source derivatives from being added under `sources/`
