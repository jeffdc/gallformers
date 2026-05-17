---
status: raw
created: 2026-05-15
updated: 2026-05-16
epic: source-ingestion
relates: [9314]
---

# Source ingestion: OCR support for scanned PDFs

## Context

The `north-star-v0` pipeline only handles born-digital PDFs (real text layer). Scanned/image-only papers produce empty or garbage output. This is currently called out as a known limitation in the alpha-tester README, but the path to actually supporting scanned papers needs its own execution matter.

Most BHL (Biodiversity Heritage Library) papers in our corpus are OCR scans. The Philippines paper in `test-corpus/` is a representative example: BHL-sourced, scanned, currently unprocessable end-to-end.

This work is scoped in `9314` as Phase 4 ("Real OCR for scanned papers"); this matter is the concrete execution track for that phase.

## Scope

### 1. Document profiling stage

Add a `profile_document` stage that runs before extraction and characterises each page:

- page count
- text density per page (chars / page area, or a similar heuristic)
- scan-risk classification (born-digital / mixed / scan)

Output is consumed by routing logic to decide whether to send a page through pymupdf, a deterministic OCR engine, or a vision-model OCR fallback.

### 2. OCR fallback stage

Add `ocr_fallback` that runs only on pages flagged as scans:

- OCRmyPDF / Tesseract for clean scans (cheap, deterministic)
- Provider vision OCR for degraded pages (Mistral OCR, RolmOCR, olmocr via DeepInfra/OpenRouter)
- Per-page cache keyed by image hash
- Output integrates into the same `raw_text.jsonl` schema as the born-digital path (block id, page, char offsets)

The Python harness already has an OCR module at `services/source-ingestion/src/ingest/ocr.py` that can serve as the reference implementation.

Replace the misleading "ocr_fallback" code path in `priv/python/pdf_text_extractor.py` (Elixir-side pipeline).

### 3. BHL boilerplate strip — broaden for real BHL documents

`preprocess.strip_bhl_boilerplate` currently looks for `biodiversitylibrary.org` in the first 500 chars + a `"This page intentionally left blank"` marker. Real BHL downloads (almost always OCR scans) interleave portal URLs through normal text and don't match this pattern. The Philippines paper in `test-corpus/` exhibits this and currently passes through the strip rule untouched.

When OCR support lands, examine actual BHL outputs and broaden the rule so cover-page/portal text is dropped consistently. Folded in from matter `7a83` (was originally listed as a c744 polish follow-up; reclassified here because BHL papers are almost entirely OCR scans).

## Out of scope

- Server-side bundle ingestion + WCVP enrichment (matter `415f` / `9314` Phase 6)
- Review UI changes for OCR provenance (covered by `9314` Phase 6)
- Marker / Docling evaluation (deferred per `9314`)

## Human test

Process a scanned BHL paper (e.g., the Philippines paper in `test-corpus/`) end-to-end with `north-star-v0` and receive a bundle whose evidence quotes actually appear on the OCR'd page text.

## Phase 1 design — whole-document OCR trigger (2026-05-16)

This phase implements the minimum-viable OCR fallback: a single new pipeline stage that detects scanned PDFs by text density and runs ocrmypdf on the whole document when triggered. The richer per-page profiling + mixed-routing model in section 1 of this matter remains as follow-up.

### Decisions

- **Tool:** `ocrmypdf` (wraps tesseract + ghostscript). Free, deterministic, produces a new PDF with embedded text layer so the existing `extract.py` keeps working unchanged. Vision-LLM OCR (the `north-star-v0-ocr.yaml` stub's olmOCR direction) deferred — swap is one stage rewrite if tesseract quality turns out insufficient on the eval set.
- **Trigger:** per-document auto-detect on `avg_chars_per_page`. Threshold configurable in pipeline YAML; default 100. Whole-document, not per-page (both initial target papers are uniformly image-only; mixed-mode adds bookkeeping for minimal gain). Pipeline-level overrides: `enabled: auto|always|never`.
- **Placement:** new `ocr` stage between `extract` and `preprocess`. Adds `"ocr"` to `VALID_STEPS`. New module `src/ingest/ocr.py`. Stage runs after pymupdf's first-pass extraction so the density check has data to evaluate; if triggered, replaces the `RawTextBlock` list before `write_jsonl`. (Note: matter body previously claimed `ocr.py` already existed — it does not. Stale reference, possibly from the old Elixir harness.)
- **Caching:** sidecar `output/<source-id>/source.ocr.pdf.cache.json` with `{pdf_sha256, ocrmypdf_version, language, force_ocr}`, mirroring the existing `_is_cache_valid` / `_write_cache_sidecar` pattern. Manifest `StageRunRecord` captures the OCR provenance (tool, version, trigger reason) as a separate concern from cache validity — both artifacts exist.

### Success criteria

After this phase ships:
- Loxaulus (source 103) and Triggerson (source 117) move out of `EXCLUDED` in `eval/pdf_source_map.py`.
- `uv run python eval/match_descriptions.py` shows ≥70% block match (Tier B) for both.
- No regression on currently-passing sources (the auto-detect threshold should leave them on the native extract path).

### Wall-time expectation

First OCR run of a scanned paper: ~5-10 min on M-series CPU. Subsequent runs: cache hit, seconds.

### Out of scope for this phase (remains in scope for the matter)

- Per-page profiling + mixed pymupdf/tesseract/vision-LLM routing (section 1 of this matter).
- BHL boilerplate strip broadening (section 3) — easier to revisit once we can see what real OCR'd BHL output looks like.
- Vision-LLM provider OCR fallback for cases tesseract can't handle.

