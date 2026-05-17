---
status: raw
tags: [design]
created: 2026-05-16
updated: 2026-05-16
epic: ingestion
---

# Python bundle import for review workspace (alpha)

# Python bundle import for review workspace (alpha)

## Goal

Pivot the existing Elixir-side source-ingestion review workspace (currently on branch `workspace-gall-editor`, never merged) to consume bundles produced by the Python ingestion pipeline at `services/source-ingestion/`. Ship an alpha to production for a single savvy alpha user (cofounder). End-to-end loop: upload bundle → human review/edit → commit to live `species`/`galls`/`hosts`/etc. tables.

## Context

- Python pipeline (already on `main`, PR #546) produces a `bundle.tar.gz` per paper containing `review_artifact.json` + `source.pdf` + supporting files. Four sample bundles live in `services/source-ingestion/output/{cuesta,mutun,cook,nicholls}`.
- `workspace-gall-editor` (26 ahead of main, 11 behind) carries the entire review workspace UI plus an Elixir-side ingestion pipeline (Oban workers, LLM clients, pipeline configs, SSE streaming) that the Python pivot supersedes.
- The two systems' data shapes line up unexpectedly well — same trait vocabulary (color/shape/texture/walls/cells/alignment/plant_part/form/season + detachable), same `{original, suggested[]}` per-trait shape, same hosts-as-list model. Most of Python's extra richness lives in *evidence pointers* per field (block_id, page, char offsets, quote, support_status, confidence) which the Elixir schema doesn't store.
- Related: superseded UI plan in matter 415f-species-review-workspace-redesign (lives on `workspace-gall-editor`, not main). 415f's UI/UX design is still authoritative; only the implementation-plan portion is superseded.

## Key decisions

1. **Two stages.** Stage 1 = minimum-change pivot, ship to prod. Stage 2 = surface Python's richer signals (evidence pointers, support_status badges, confidence buckets, warnings). This matter covers Stage 1 only.
2. **Preservation strategy = tag, not branch surgery.** Tag `workspace-gall-editor` HEAD as `archive/elixir-snapshot-2026-05-16` and push. No attempt to clean-isolate the Elixir pipeline backend. If we ever pivot back to Elixir, we revive from the tag.
3. **Branching:** create `alpha-ui` from `workspace-gall-editor` HEAD. **Merge `main` into `alpha-ui` as the first real step** (workspace-gall-editor is 11 commits behind main; resolve those conflicts up front against current main before doing anything else). Squash-merge `alpha-ui` to `main` at the end — squash diff = net-new feature, no deletions visible to reviewer.
4. **Scope = L3 (full commit-to-DB loop), not L2.** The existing branch already has commit-to-DB wired (`SourceIngestionSpeciesReview` operates on `extraction_payload` + `review_payload`). L2 would mean ripping that out, which is more work than keeping it.
5. **Skip dedup entirely for Stage 1.** No minhash/fingerprints, no `needs_duplicate_review` gate. Every uploaded bundle creates a fresh `SourceIngestion`. Re-enable in Stage 2 if it earns its keep.
6. **Skip pipeline-lifecycle states.** On bundle import, jump straight to `status: "needs_review"` / `processing_stage: "review"`. Leave the unused enum values in place (cheap dead code) rather than re-doing the enum.
7. **Preserve Python richness in one new JSONB column.** Add `raw_extraction :map` to `source_ingestion_species` — store the full Python record per gall verbatim. Stage 1 UI ignores it; Stage 2 reads from it. Free insurance against data loss.

## Architecture

### Data flow

```
Python pipeline  →  bundle.tar.gz on disk  →  admin uploads via LiveView
                                                    ↓
                                          BundleImporter (Elixir)
                                          - extract tar to tmp
                                          - parse review_artifact.json
                                          - validate shape
                                          - write source.pdf + raw_text + JSON to S3
                                            via existing Storage.SourceArtifacts
                                          - create SourceIngestion (status=needs_review)
                                          - create N SourceIngestionSpecies in one txn
                                                    ↓
                                          existing /admin/ingestion-review/:id/show
                                                    ↓
                                          existing workspace LiveView (per record)
                                                    ↓
                                          existing commit-to-DB path
                                          (SourceIngestionSpeciesReview)
                                                    ↓
                                          real species / galls / hosts rows
```

### Field mapping summary

Maps cleanly (no transformation work):
- Paper metadata: title, authors, year, doi, pdf_sha256, preprocessed_text_sha256
- Per-record: extracted_name, extracted_authority, gall_species (name/authority/family/order), hosts (name/authority/family), aliases, all 9 trait values + detachable, description prose, location

Stored raw, not surfaced in Stage 1 UI:
- All per-field evidence pointers (block_id, page, char offsets, quote)
- support_status / confidence per field
- confidence_bucket per record
- Per-record warnings, top-level warnings
- Taxonomy ranks beyond family/order (kingdom, phylum, class, suborder, subfamily, tribe, genus, subgenus)
- common_names, taxonomy_lookups, record_id/candidate_id

Dropped / left nil:
- `confidence` float on extraction_payload (Python has categorical bucket; mapping deferred)
- `title_fingerprint`, `author_fingerprint`, `normalized_title`, `minhash_signature` (dedup signals; no dedup in Stage 1)
- `duplicate_of_source_ingestion_id`, `pipeline_config_id`, `error_*`, `failed_at`

## Sequencing

**Day 1**
1. Tag + push `archive/elixir-snapshot-2026-05-16` from `workspace-gall-editor` HEAD
2. Create `alpha-ui` from `workspace-gall-editor` HEAD
3. **Merge `main` into `alpha-ui`** — resolve conflicts, get `mix compile` + `mix test` green (first risk gate)
4. Delete `lib/gallformers/ingestion_pipeline/`, `lib/gallformers_web/live/admin/pipeline_config_live/`, dedup logic in ingestions.ex / lifecycle.ex / source_ingestion_creation.ex, related tests, related routes. Compile green.
5. Migration: add `raw_extraction :map` to `source_ingestion_species`. Update schema + changeset cast list.
6. New `Gallformers.Ingestions.BundleImporter`: parses extracted bundle dir → produces `SourceIngestion` + `SourceIngestionSpecies` attrs → creates rows in one transaction. Pure-ish; unit-test against the 4 sample bundles.

**Day 2**
7. New admin LiveView for bundle upload (file picker for `bundle.tar.gz`; extract via `:erl_tar`; invoke `BundleImporter`; redirect to existing `ingestion_review_live/show`).
8. Wire route, link from admin dashboard.
9. Smoke test end-to-end with cuesta bundle: upload → workspace → edit → commit → verify real DB rows created. Repeat with mutun/cook/nicholls.
10. Fix breakage as it surfaces (slush time).
11. Squash-merge `alpha-ui` → `main`, push, deploy.

## Non-goals (Stage 1)

- Evidence-pointer display in UI; PDF preview / scroll-to-evidence
- support_status / confidence_bucket badges
- Document-level + per-record warnings panel
- Genus/subgenus etc. on gall identity (only family/order surface)
- Dedup detection / `needs_duplicate_review` gate
- Re-ingestion / update of existing ingestions (each upload is fresh)
- Background processing — upload is synchronous (small bundles, one user, acceptable)
- 100% feature parity with what `workspace-gall-editor` *could have* done; rough edges OK for one savvy alpha user

## Risks

- **Workspace LiveView depends on a pipeline-driven field we missed.** Mitigation: after Day 1 step 3 (merge main in) and step 4 (deletions), `mix compile` + `mix test` must be green before proceeding. Missing references will surface there.
- **S3 storage paths** — `Storage.SourceArtifacts` is the canonical abstraction (cab4 refactor); hand it the bundle contents and let it own the prefix. Don't roll our own S3 layout.
- **Tar extraction safety** — `:erl_tar` from stdlib. Single savvy user; skip hardening (no symlink/path-traversal checks). Worth a note when we widen access.
- **Squash-merge size optics** — diff against main is purely additive (deletions on `alpha-ui` net to zero in the squash since they were never on main). PR description should explain lineage and link to `archive/elixir-snapshot-2026-05-16` tag.

## Stage 2 preview (not in scope)

- Surface evidence pointers per field; PDF preview with scroll-to-page
- support_status badges + confidence_bucket on each record
- Per-record + document warnings panel
- Genus / subgenus in identity workspace
- Re-ingestion (update existing on same DOI / pdf_sha256)
- Background bundle processing via Oban (cheap; just file IO)
- Re-enable dedup keyed on DOI / pdf_sha256

## References

- Python pipeline: `services/source-ingestion/` (README + 4 sample bundles in `output/`)
- Archive tag (to be created): `archive/elixir-snapshot-2026-05-16` from `workspace-gall-editor` HEAD
- Related design (on workspace-gall-editor, will arrive on alpha-ui via merge): `415f-species-review-workspace-redesign` — still authoritative for UI/UX patterns
- Archived precursors on workspace-gall-editor: `7c67`, `fa48`, `a4fe`, `97c4`, `6c66`, `cab4`, `db32`, `feac`, `f037`, `7fda`, `2f2d`

