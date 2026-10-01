---
status: planned
created: 2026-04-21
updated: 2026-09-13
epic: source-ingestion
relates: [fa48]
blocks: [7fda]
parent: 7fda
---

# Persisted source ingestion review queue and detail workflow

## Scope

Replace the current ingestion-review PoC with the real DB-backed reviewer workflow described in `fa48`, using the schema and review state model from `664d`, the review-ready pipeline payload from `a80e`, and the explicit duplicate-review model now defined by `93b8`.

This matter should feel like the UI/workflow realization of `7fda`, not an isolated LiveView rewrite.

## Must Reflect From `7fda` And `93b8`

This matter should preserve these assumptions:
- the current LiveView is a PoC reference, not the target architecture
- the reviewer queue and detail flow are backed by persisted ingestion state in Postgres
- duplicate review is a first-class workflow state, not an implicit side effect
- source resolution happens before gall-review work begins
- normal source/gall review should remain blocked until duplicate disposition is resolved
- completion is derived from all ingestion-species items being resolved
- the gall workspace needs gall-level prose and separate trait evidence, not just raw local artifact inspection

## Target Workflow

### 1. Landing page / work queue

Build the persisted queue view envisioned by `fa48` and reinforced by `7fda`, updated for explicit duplicate handling:
- list persisted ingestions, not local output folders
- show title, species/review counts, status, uploaded date, and uploader as available
- show duplicate-review items distinctly from normal review-ready items
- allow filtering of active vs complete work
- entry point for creating new ingestions should ultimately align with supported production input types from `7fda`

### 2. Duplicate review on the ingestion detail page

Implement a DB-backed duplicate-review section for an ingestion whose status is `needs_duplicate_review`.

It should:
- show the candidate duplicate ingestions from `source_ingestion_duplicate_candidates`
- show the evidence payload in an explainable way
  - DOI match
  - exact preprocess hash match
  - title match / near-match
  - author fingerprint overlap
  - year comparison
  - fuzzy text similarity estimate
- allow reviewer actions such as:
  - confirm duplicate / merge into existing canonical ingestion
  - reject candidate and keep this ingestion separate
  - optionally promote this ingestion as canonical if it is materially cleaner

Until duplicate disposition is resolved, the standard source and gall review workspace should remain locked.

### 3. Source detail page after duplicate disposition

Implement the normal DB-backed detail page for a single ingestion once duplicate state is resolved.

It should:
- show extracted source metadata from the ingestion record
- allow mapping to an existing source or creating a new one
- keep gall review locked until the source is resolved
- show the set of extracted gall items from `source_ingestion_species`
- reflect persisted per-gall statuses rather than transient assigns

### 4. Gall review workspace

Implement the per-gall review experience described in `fa48`, backed by persisted ingestion-species state.

At minimum, the workspace should support:
- extracted gall identity and matching state
- extracted host identity and mapping state
- trait review using proposed values plus raw evidence phrases
- display/editing of the gall-level prose block intended for `species_source.description`
- progression of the per-gall review status toward resolution

The exact UI shell can adapt during implementation, but the information architecture should remain faithful to `fa48`.

## What This Includes

- landing queue page for persisted ingestions
- distinct duplicate-review presentation and actions on ingestion detail
- DB-backed ingestion detail page for normal source/gall review once duplicate state is resolved
- source mapping/create flow that unlocks gall review after resolution
- persisted per-gall review state and completion logic
- rendering of the structured extraction payload from `a80e` without requiring raw artifact file spelunking
- retirement/replacement of the current PoC's local-output-driven workflow path

## Constraints

- reviewer state must live in Postgres, not just LiveView assigns
- do not keep compatibility with the current PoC file layout as if it were the canonical system
- do not redesign extraction payload shape independently of `a80e`; consume the review-ready payload produced there
- preserve the duplicate-first, then source-first, then gall-review workflow implied by `7fda` and `93b8`
- completion should apply to canonical / non-duplicate review work, not to unresolved duplicate candidates

## Non-Goals

- production pipeline implementation itself
- Python-driven review tools
- turning this matter into a generic admin redesign unrelated to ingestion

## Deliverable

A production source-ingestion review workflow that matches the direction of `fa48` and `7fda`, updated for `93b8`: persisted queue, explicit duplicate-review state and actions, persisted detail page, source-gated gall review, gall-level prose and trait evidence, and completion based on resolving all ingestion-species items rather than on local artifact files.


## Review requirements retained from ce28 and db32 consolidation

ce28 and db32 are being closed with unfinished work assigned to active owners. This section supersedes conflicting old a80e/PoC payload assumptions: consume the current versioned Python producer bundle, following the revised fa48 design and 7fda production boundary rather than introducing another extraction schema.

Implement persisted, evidence-aware decisions: show exact source context, verifier status, uncertainty and conflicting values; approve source metadata separately from biological facts; support accept, edit with evidence preserved/replaced, reject with reason and insufficient evidence; and make entity mapping/create decisions explicit through normal domain APIs. No confidence-based auto-writeback, silent synonym assertion or silent overwrite of curator conclusions. Persist review progress and make reviewer edits/rejections usable by the 9314 evaluation process without inventing a permanent domain store of every unaccepted claim.

Wire approved domain changes to 7fda's accepted-assertion/source-evidence boundary and explicit final-markdown publication using the existing SourcePublisher operation. Keep private source/bundle/intermediate artifacts private; only intentionally approved final markdown gets a public sources/ path. Workflow completion must not conceal unresolved approval or publication failures. Deployment/access verification is owned by 7fda, not certified by db32's closure.

The separate gall/shared-taxon admin-safety design remains subject to 4dcd/2cb2 approval. Preserve duplicate-first and source-first review gating while rebasing its implementation on current contracts.
