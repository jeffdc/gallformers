---
status: raw
created: 2026-05-12
updated: 2026-05-15
epic: source-ingestion
relates: [c744]
---

# Source ingestion pipeline polish: follow-ups from c744

## Context

Two concrete, non-blocking follow-ups from `c744` (Python ingestion
pipeline: artifacts as the contract). c744 is being closed as `done`
because Phase A is complete, all four real Phase B prompts have been
written and iterated, the production model set is settled, and the
pipeline runs the full corpus end-to-end with prompt-SHA-aware
resumability. These remaining items were explicitly identified during
that work and deferred — none block any current functionality.

Reference: `services/source-ingestion/docs/extract-facts-model-bakeoff.md`
captures the model decision rationale; the c744 matter body documents
the broader implementation history.

A third polish item — broadening `preprocess.strip_bhl_boilerplate` — has
been moved to matter `4fef` (OCR support for scanned PDFs), since nearly
all BHL papers are OCR scans and the boilerplate work is naturally part
of bringing OCR support online.

## 1. Elixir mix task for vocab regeneration + CI guard

`schemas/gallformers-vocab.json` was created by hand-running a SQL query
against the `gallformers_dev` filter_fields tables and dumping the
result. That works but the JSON drifts from the live DB the moment any
admin adds/removes a value via the UI.

The matter's design called for a mix task in Elixir that exports trait
enums to the JSON file, plus a CI guard that fails if regenerating the
JSON produces a diff. Both pieces are outside the
`python-ingestion-pipeline` worktree (they live in main Elixir code).

What to build:

- `mix gallformers.export_trait_vocab` — queries the FilterFields tables
  (color, shape, texture, walls, cells, alignment, plant_part, form,
  season) and writes `services/source-ingestion/schemas/gallformers-vocab.json`
  in the same format the python pipeline already consumes (see the
  existing JSON for the exact shape).
- CI step: run the mix task, then `git diff --exit-code
  services/source-ingestion/schemas/gallformers-vocab.json`. Fails the
  build if the checked-in JSON is stale.

Effort: small. The JSON shape is fixed; one mix task with a few SELECTs.

## 2. On-disk `normalized_text.jsonl` `section_id` linkage

`pipeline.py` writes `normalized_text.jsonl` immediately after the
`preprocess` stage, BEFORE the `sectionize` stage runs and assigns
`section_id` to each block. As a result, every row in the JSONL has
`section_id: null` even though the in-memory blocks (used by every
downstream stage) have `section_id` correctly populated.

Functional impact: zero on the python side — the in-memory data is
correct. The bundle's JSONL is technically stale, but the bundle also
contains `sections.json` which has the authoritative span_id → section
mapping, so server-side consumers can compute it.

Cosmetic / cleanup. The cleanest fix is to defer the JSONL write until
after `sectionize` runs. Slight reordering of stage records (preprocess
no longer claims `artifacts_written=["normalized_text.jsonl"]`;
sectionize claims it instead).

## What's NOT in this matter

These are explicitly out of scope per c744 and remain so:

- OCR pipeline (matter `4fef`; broader phasing in matter `9314`)
- Marker / Docling evaluation (deferred)
- Server-side bundle ingestion + WCVP enrichment (matter `415f` /
  Phase 6 work)
- Beta UX / distribution
- GBIF↔WCVP disagreement resolution (server-side)

