---
status: raw
created: 2026-05-15
updated: 2026-09-13
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


## Requirements retained from ce28 on consolidation

ce28 is being retired as superseded; this matter owns its remaining document-profiling/OCR outcomes. Continue from the current Python producer/bundle contract (c744 baseline), not a mandatory port into the obsolete Elixir-stage layout described above.

In addition to the scope above, preserve these acceptance concerns:
- Profile mixed documents per page, including text density, suspicious characters/spacing/line breaks, scientific-name damage, image coverage and table/column risk; route OCR only where needed.
- Preserve page/block identity, positions/bounding boxes where available, extractor/OCR method and version, and available quality/confidence signals in the shared evidence artifact contract. Do not fabricate confidence that an engine does not supply. Keep raw text immutable and normalized evidence traceable back to it.
- Compare source-provided BHL OCR with local/provider extraction on representative documents; choose by measured page quality, preserving alternatives/provenance where they differ materially. Source-provided OCR is not automatically authoritative.
- Cache page OCR by image/content and relevant configuration identity, and handle easy scans versus degraded scans through measured routing. The old list of OCR engines is a candidate set, not a commitment to implement every one.
- Demonstrate that scanned and mixed documents retain real, resolvable evidence for names, host relationships and gall traits despite columns, tables and boilerplate. Feed representative scans and OCR-damaged-name cases into the 9314 gold-set evaluation.

Full-source completion is tracked in db6f; born-digital preparation and supported processing need not wait for this matter. Closing ce28 does not mark OCR as delivered.

