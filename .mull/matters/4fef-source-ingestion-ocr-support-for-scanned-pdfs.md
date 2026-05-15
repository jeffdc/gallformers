---
status: raw
created: 2026-05-15
updated: 2026-05-15
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

