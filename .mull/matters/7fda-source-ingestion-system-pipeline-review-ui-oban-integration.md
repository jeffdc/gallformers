---
status: planned
tags: [design]
created: 2026-03-04
updated: 2026-09-13
epic: source-ingestion
relates: [fa48]
needs: [7c67]
---

# Source ingestion system — pipeline, review UI, Oban integration

## Source Ingestion System — Rebased Plan

Rebased on repo state as of 2026-04-21, with the duplicate-detection design now resolved by `93b8`.

This matter remains the umbrella for productionizing source ingestion, but its scope is explicitly different from the earlier greenfield design.

## Current State

- `dd3a` (Oban infrastructure) is complete as of 2026-04-21. Oban queues, plugins, migrations, dashboard, and operator docs are in place.
- `881c` (unified species creation and reclassification API) is complete as of 2026-04-01. `c836` was folded into `881c`.
- A superadmin-only ingestion review PoC exists on main. It shells out from LiveView to the Python pipeline, reads/writes local artifact files under `services/source-ingestion/output/`, and allows manual source/species linking. This is useful reference behavior, but it is not the production architecture.
- There is currently no persisted ingestion domain model in Postgres (`source_ingestions`, `source_ingestion_species`, duplicate-candidate tables, etc. do not yet exist).
- There is no production ingestion data to preserve. We are free to choose sane ingestion, dedup, and artifact semantics now.

## Rebased Architecture Decision

### Production system is Elixir-native

**Decision:** The production ingestion pipeline will live in the Phoenix app and run via Oban workers. Elixir owns workflow state, orchestration, retries, status transitions, DB writes, PubSub progress, duplicate-review state, and artifact bookkeeping.

**Why:**
- The first production version must introduce new Postgres schema and workflow state.
- Letting Python write directly to Postgres would duplicate schema knowledge, validations, and transaction rules outside the app.
- Adding an API/bridge between Python and Elixir would create a second production system and a protocol boundary to maintain.
- Most planned stages are workflow/document-processing tasks rather than Python-ecosystem-dependent ML tasks.

### Python stays as a narrow tool, not the production orchestrator

**Decision:** Keep Python for the places where it has clear leverage, but do not let Python own production ingestion state.

**Python remains useful for:**
- PDF extraction via `pymupdf4llm`
- OCR fallback / experiments if needed
- prompt iteration and corpus experiments
- evaluation scripts and baseline generation

**Python must not do in production:**
- direct DB writes
- status transitions
- orchestration of later pipeline stages
- duplicate-review decisions
- source/species mapping logic
- artifact bookkeeping beyond returning extracted text

If Python is invoked from production, it should be a narrow file-in/file-out adapter for PDF extraction only.

## Stage Ownership

### Elixir-owned production stages

These stages will be implemented in Elixir and run as Oban jobs or job steps:
- `preprocess`
- `hash_and_dedup`
- `llm_clean`
- `metadata`
- `data_extract`
- `assemble`
- `upload`
- all ingestion DB record creation / updates
- all duplicate-candidate creation / resolution transitions
- all progress broadcasting and reviewer state transitions

### Python-owned narrow stages

- `extract` for PDF input via `pymupdf4llm`
- optional OCR fallback if we keep that capability

### Input types

- **PDF**: supported in production; extraction may initially remain Python-backed
- **URL**: supported in production; extraction should be implemented in Elixir
- **Plain text**: supported in production; handled directly in Elixir
- **DOCX**: not required for the first production slice unless needed immediately; may be added later with either Elixir or external-tool/Python backing

## DB Schema

The first production slice must introduce persisted ingestion state in Postgres. Exact Ecto schema names/columns can evolve during implementation, but the model should be:

### `source_ingestions`
- `id` (PK)
- `input_type` — enum-like field such as `pdf`, `url`, `text`, `docx`
- `status` — ingestion lifecycle status such as `processing`, `needs_duplicate_review`, `needs_review`, `complete`, `failed`
- `processing_stage` — current stage or last completed stage for reviewer/operator visibility
- exact and fuzzy duplicate signals owned by the ingestion row, including fields such as:
  - `raw_input_sha256`
  - `preprocessed_text_sha256`
  - `normalized_doi`
  - `normalized_title`
  - `title_fingerprint`
  - `author_fingerprint`
  - `publication_year`
  - `minhash_signature` or equivalent fuzzy-text signature storage
- extracted / normalized source metadata (`title`, `authors`, `year`, `doi` as appropriate)
- `duplicate_of_source_ingestion_id` or equivalent canonical-link field for confirmed duplicates
- nullable `source_id` FK to `sources`
- `artifacts_path` — canonical storage prefix for this ingestion's artifacts
- `uploaded_by` / timestamps
- error fields needed for failed runs and operator debugging

### `source_ingestion_duplicate_candidates`
- subject ingestion FK
- candidate matching ingestion FK
- candidate status such as `pending`, `confirmed`, `rejected`, `auto_confirmed`
- evidence payload summarizing the signals that triggered the candidate
- reviewer / timestamp fields needed for auditability

This table is the source of truth for duplicate-review workflow. Do not try to encode the whole duplicate system as alias hashes on the ingestion row.

### `source_ingestion_species`
- `source_ingestion_id` FK
- extracted gall name / authority fields sufficient for review UI display
- `species_id` nullable FK
- review status such as `pending`, `mapped`, `created`, `skipped`, `complete`
- per-gall extracted prose block / structured extraction payload as needed for the review UI

The exact schema should be optimized for the reviewer workflow rather than mirroring the PoC file layout.

## Deduplication

`93b8` resolved the duplicate strategy. The production system should follow it directly.

### Core model

Dedup is **submission-centric, multi-signal, and review-first**.

That means:
- each submission becomes its own `source_ingestions` row
- dedup creates relationships between ingestions rather than collapsing all inputs into one row immediately
- there is no single universal article identity key
- DOI is the strongest hard identity signal when present
- exact preprocess hash is an exact normalized-text signal, not the full cross-format identity model
- fuzzy same-article detection should use deterministic document similarity, with MinHash over token shingles as the preferred v1 approach

### Decision ladder

The production ladder should be:
1. create the ingestion row immediately with an ingestion-id-based artifact prefix
2. extract raw text and preprocess deterministically
3. compute duplicate signals
4. check candidates in order:
   - exact DOI match → auto-confirm duplicate
   - exact preprocess hash match with non-conflicting metadata → auto-confirm duplicate
   - strong metadata match → duplicate candidate for reviewer confirmation
   - high MinHash similarity, preferably with metadata support → duplicate candidate for reviewer confirmation
5. if no strong duplicate signal exists, continue into expensive LLM stages
6. later metadata extraction may enrich stored signals for future submissions, but does not replace the early dedup pass

### Storage semantics

Artifacts should be keyed by ingestion ID, not by preprocess hash or DOI.

Use a per-ingestion prefix such as:
- `source-ingestions/<ingestion-id>/...`

When duplicates are confirmed:
- keep each ingestion row and its own artifact prefix for provenance
- link duplicates to the chosen canonical ingestion
- allow a reviewer/operator to promote a cleaner ingestion as canonical later if needed

## Review UI Direction

The existing LiveView is a PoC reference, not the target architecture.

The production UI should follow the `fa48` information architecture, updated for explicit duplicate review:
- landing page / work queue of persisted ingestions
- duplicate-review state visible in the queue alongside normal review-ready work
- source detail page backed by DB state, not local output files
- source mapping and gall-review workflow available only after duplicate disposition is resolved
- per-gall focused review workflow with persisted status
- completion derived from all gall items being resolved

Key implication: reviewer state must be persisted in Postgres. Socket-only state and local artifact inspection are insufficient.

## Extraction Contract Change: Gall-Level Prose

The `data_extract` contract still needs to evolve from the PoC.

For each gall under review, we need:
- `description`: the full prose block from the source that applies to that gall species and will become `species_source.description`
- `traits.{trait}.original`: the exact phrase(s) supporting each trait value

The production review UI depends on this richer output. The current morphology-only `description` shape is not enough.

## Artifact Storage

Artifacts should be stored under a canonical per-ingestion prefix (S3/object storage), not only under local `services/source-ingestion/output/` directories.

Artifacts to persist:
- extracted text
- preprocessed text
- llm-clean output
- metadata JSON
- data-extract JSON
- assembled markdown
- any useful debug/error artifact needed for operators

Original uploaded files are not required for the first production slice unless we later identify a strong operational reason to keep them.

## Auth / Access

The PoC is currently superadmin-only. Production should move to a dedicated ingestion role such as `ingestion-admin` rather than tying the feature permanently to `superadmin`.

## Implementation Strategy

This matter should be executed in this order:

1. Dedup strategy is now decided in `93b8`
2. Add persisted ingestion schema and contexts in Elixir (`664d`)
3. Port production-critical stages to Elixir and implement the Oban-backed pipeline core (`a80e`)
4. Keep Python only as a thin PDF extraction adapter where needed
5. Build the real review queue/detail workflow, including duplicate-review state, on top of DB-backed state (`7c67`)
6. Add artifact upload/storage
7. Tighten auth and operator workflows

## Python Research Harness

The Python code under `services/source-ingestion/` remains valuable and should stay in the repo as a research/evaluation harness.

Use it for:
- prompt iteration
- corpus experiments
- baseline generation
- extraction quality evaluation
- trying ecosystem-heavy document processing ideas before deciding whether they belong in production

But do not let it become a second production system.

## Documentation Requirements

Update as implementation lands:
- architecture docs for ingestion pipeline boundaries and why production orchestration is Elixir-owned
- runbooks for ingestion job monitoring, duplicate review, failure handling, and artifact inspection
- CLAUDE.md / CODING_STANDARDS.md for Oban usage and ingestion implementation conventions where needed

## Relationship To Other Matters

- `dd3a` is complete and no longer a blocker
- `881c` is complete and satisfies the species creation/reclassification prerequisite
- `93b8` now defines the duplicate model that `664d`, `a80e`, and `7c67` should implement
- `fa48` remains the target UI direction for reviewer workflow, with duplicate handling now made explicit by `93b8`

## Summary

`7fda` is no longer "wrap the Python PoC and get it onto main." The repo already has the PoC. The remaining work is to build the real, persisted, Elixir-native ingestion system on top of Oban and Postgres, with explicit duplicate signals, explicit duplicate-review workflow, and ingestion-owned artifact/state semantics throughout.


## Consolidation of db32 and ce28 — current production responsibilities

Jeff authorized preserving the remaining requirements in their active owners and closing db32 and ce28. This section supersedes conflicting architecture, storage, and release assumptions earlier in this matter; it does not authorize implementation or approve the proposed taxonomy foundation.

### Current boundary

The versioned Python producer bundle in services/source-ingestion/ is the existing baseline (developed under c744), not work to recreate or port wholesale to Elixir. Elixir owns durable production orchestration through Oban, persisted review state, authorization, source/entity resolution, accepted-claim writeback, and publication. Python must not write production domain records. No persistent Python service or idle GPU is required by the inherited design. Reuse current schemas and implementations; do not revive ce28's illustrative JSON or obsolete stage/file layout as a second contract.

### Remaining storage release gate inherited from db32

The repository has the private/public storage split and SourcePublisher.publish_markdown/2; deployment was NOT verified by the portfolio audit. Before production ingestion/publication is released, record deployment evidence that:
- gallformers-private exists with all four S3 public-access-block settings enabled and no policy granting public access.
- Application configuration and IAM permit the required private read/write/list/delete operations; private originals and intermediate artifacts cannot be fetched anonymously.
- Incomplete multipart uploads expire after seven days; this is not an authorization for unrelated object-retention changes.
- Input documents, raw/normalized text, manifests, review bundles and working/debug artifacts are stored privately under the ingestion-owned namespace. Preserve the existing source-ingestions/{ingestion_id}/... boundary; map current bundle artifacts through existing APIs rather than resurrecting old producer filenames. Preserve the original document and immutable evidence artifacts needed to audit accepted claims; the earlier statement that original uploads are unnecessary is superseded for this workflow.
- Approved final markdown alone is intentionally published to the public sources/{source_id}/{snake_cased_truncated_title}.md path through the existing publisher/path builder. Copy bytes without a second normalization pass; verify deterministic republishing and explicit failure when the private source artifact is missing. Do not publish arbitrary pipeline artifacts or invent public URLs for them.

Exercise the actual deployed private/public path with the application's credentials and anonymous access checks before recording this gate as satisfied. Repository declarations alone are insufficient. db32 closure transfers this outstanding gate here; it does not certify deployed infrastructure.

### Remaining production integration inherited from ce28

- Consume and validate the existing versioned producer bundle, manifest/hashes and evidence references. Resolve duplicates and the existing/new Source before biological review; preserve auditable source text, names as written, and conflicting evidence rather than silently normalizing it away.
- Humans explicitly approve database changes; extraction confidence or verifier status never grants an automatic writeback shortcut. Only accepted assertions enter the domain provenance queries, with specific supporting sources/evidence. Private candidate/review artifacts are not a mandate for a database of every rejected or unaccepted claim.
- Support both directions of accepted provenance: why Gall X has Host Y, and all accepted host assertions attributable to Source Z. Broad legacy source links cannot be promoted into invented per-fact support.
- Integrate the persisted reviewer (7c67, designed in fa48), domain writeback, and explicit final-markdown publication. Prove one real paper can reach reviewed accepted data and its published artifact without losing source evidence or exposing intermediates. Preserve curator work and avoid duplicate assertions/evidence when retrying or reprocessing.
- Own durable retry/status/operator behavior, bounded provider concurrency, failure reporting, selected-stage rerun integration, and recording costs/latency/config provenance. Producer-side evaluation and hardening belong in 9314; OCR belongs in 4fef; vocabulary drift prevention belongs in 7a83.
- Full existing-source processing is the separately tracked db6f campaign, not satisfied by a successful sample or the producer's iteration corpus.

Taxonomy separation remains proposed, not approved. If chosen, establish the bounded gall/taxon/accepted-provenance foundation and its admin-safety gate before substantial production approval/writeback integration. This consolidation does not make unrelated taxonomy expansion a prerequisite.
