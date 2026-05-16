---
status: raw
created: 2026-05-09
updated: 2026-05-09
epic: source-ingestion
---

# Greenfield LLM Gall Paper Ingestion Pipeline — Synthesis Plan

Date: 2026-05-09

A clean-slate design for extracting structured gall data from academic papers. Deliberately ignores prior implementation work. Synthesizes four independent agent perspectives (Tunstall / Wei / Bengio / Shleifer) into a single best-of-breed plan.

## Constraints

- Gallformers is Elixir/Phoenix. Python is acceptable for PDF/ML tooling.
- Oban is available for background jobs.
- DeepInfra and OpenRouter accounts available for LLM/OCR access.
- No large always-on service. Run via Oban + short-lived Python subprocesses.
- Mostly English PDFs. Mix of modern born-digital and old scanned journals.

## Goals

- Extract readable raw text from PDFs, including scanned pages.
- Extract document metadata: title, authors, year, journal, volume/issue/pages, DOI, source URL, language, extraction provenance.
- Extract structured gall data:
  - gall-maker scientific names (with authority and rank)
  - common names, aliases, and `name_as_written`
  - host species associations
  - taxonomic classification and notes
  - **descriptive traits about the gall itself, not the gall-maker**
  - page/block/span evidence for every nontrivial value
- Produce review-ready candidate artifacts; humans approve database changes.

## Non-Goals

- No persistent Python web service unless evidence shows subprocess invocation is inadequate.
- Do not let the review UI shape the ingestion schema.
- Do not use LLM self-reported confidence as a substitute for evidence.
- Do not auto-write to production gall, host, taxonomy, or source records.
- Do not normalize away `name_as_written`. Historical names, synonyms, authorities, and OCR-damaged forms remain auditable.

## Guiding principles

1. **Wrong data is worse than missing data.** Gallformers is a long-lived scientific reference; a confident hallucination cited tomorrow is permanent. Abstention is a feature.
2. **Every claim is evidence-bound.** No structured field exists in the database without a character-offset citation back to the raw text, programmatically verified before persistence.
3. **Carry uncertainty; never collapse it.** OCR confidence, sample agreement, model self-report, and cross-source agreement are stored as separate signals.
4. **Conflicts are first-class.** Disagreements between sources (GROBID vs Crossref, k=k samples, extractor vs verifier) are emitted, not silently resolved.
5. **Cheapest model that hits the bar.** Default open-weights mid-tier on DeepInfra. Reach for frontier APIs only at steps where measurement justifies the spend.
6. **Ship the smallest end-to-end slice with full epistemics.** Feature-complete first with epistemics bolted on later is how scientific databases get poisoned.
7. **No idle GPU.** All ML through DeepInfra/OpenRouter. Python runs via Oban-invoked subprocesses, no persistent web service for v1.

## Architecture

Elixir/Oban orchestrates. Python subprocesses handle PDF parsing, page rendering, OCR helpers, and local document tooling. LLM/OCR provider calls go through a thin adapter (DeepInfra + OpenRouter, OpenAI-compatible).

Each stage reads immutable input artifacts and writes immutable output artifacts plus a manifest entry recording stage version, config hash, prompt version, model/provider, timestamps, token/cost, and warnings. **Stages are individually re-runnable** without redoing upstream work.

### Stages

1. **submit** — Store original PDF; SHA-256; create pipeline run with selected configuration; enqueue first stage.
2. **profile_document** — Page count; per-page text density; scan/OCR risk per page; embedded PDF metadata; language detection; flag image/table/reference/plate-heavy pages.
3. **extract_raw_text** — Born-digital pages via PyMuPDF or `pypdfium2`. Emit page-aware blocks: page, block_id, optional bbox, text, extractor name/version, char offsets. Raw text is the canonical audit artifact.
4. **ocr_fallback** — OCR only pages flagged in step 2. Cache by page-image hash. Local OCR (Tesseract or OCRmyPDF) for easy scans; provider vision/OCR (Mistral OCR, Nougat, or RolmOCR via DeepInfra) for degraded pages. Same artifact shape as native extraction.
5. **normalize_text** — Deterministic cleanup only: dehyphenation, line rejoining, header/footer removal, boilerplate stripping, simple column repair, plate-page handling. **Preserve a transform map from normalized spans back to raw block spans.** Never overwrite raw text.
6. **sectionize** — Split into logical sections: title page, abstract, introduction, taxonomic treatments, species entries, host lists, keys, tables, captions, plates, references, appendices. Chunk by structure first, token size second. Keep heading ancestry. **Mark references/bibliography as excluded from biological fact extraction unless explicitly configured.**
7. **extract_metadata** — Deterministic first: PDF metadata, DOI regex, title-page heuristics, page-range patterns. LLM (cheap model, e.g. Llama-3.1-8B on DeepInfra) fills gaps. Verify DOI/title via Crossref where available. Disagreements between sources are stored as competing claims, not reconciled silently.
8. **find_candidate_spans** — Cheap deterministic patterns + a cheaper LLM identify likely gall-relevant sections, species treatments, host association tables, descriptions. Maximize recall. Keep evidence windows small enough for focused extraction. Self-consistency at N=3 *only here*, where it's cheap and recall matters most.
9. **extract_facts** — Focused LLM calls over candidate spans + bounded context. One candidate association per gall-maker/host relationship. Extract gall morphology only:
   - **Allowed**: plant part, shape, color, size, texture, pubescence, chamber count, detachable/persistent, seasonality/phenology when tied to the gall, other gall descriptors.
   - **Disallowed (adult-trait leakage)**: antennae, wings, mesosoma, genitalia, body color, larval morphology, behavior — unless used as taxonomic context rather than gall trait.
   - Every nontrivial field includes evidence. Closed-set citation: prompt provides numbered spans `[span_id: S_42]`; schema constrains `evidence_span_ids` to those literals so the model can only *select* citations, never invent them.
   - Constrained JSON output (DeepInfra `response_format` / OpenRouter equivalent). Schema validation + retry/repair regardless.
10. **verify_claims** — Independent verification pass with **a different model family** (if extractor is Llama, verifier is DeepSeek-V3 or Claude Haiku; verifier diversity matters more than verifier capability). For each fact, ask: does the quoted evidence directly support the claim? Returns `supported`, `contradicted`, `not_enough_evidence`, or `needs_human_review`. Drop or downgrade unsupported claims before review.
11. **normalize_and_reconcile** — JSON Schema validation. Merge duplicate candidates across chunks/tables. Preserve `name_as_written` before normalization. Match host plant names against local plant data and GBIF/Catalogue of Life as suggestions. Match gall-maker names against local Gallformers data as suggestions only. Map gall trait phrases to controlled vocabulary suggestions while retaining original source language. **Emit conflicts instead of silently choosing winners.**
12. **assemble_review_artifact** — Stable artifact: document metadata, raw/normalized text refs, entities, associations, facts, evidence spans, warnings, conflicts, costs, and full provenance. Review UI consumes from this artifact; the artifact contract is independent of UI layout.

## Artifact Contract

Provenance is first-class. Every field that can affect the database has evidence.

Artifact set:

- `manifest.json` — pipeline version, source SHA, stage statuses, artifact paths/hashes, provider/model/prompt/schema versions, token usage, cost estimate, latency, warnings.
- `raw_text.jsonl` — one row per page block / OCR block: page, block_id, text, optional bbox, extractor, quality signals.
- `normalized_text.jsonl` — normalized blocks linked back to raw block IDs and offsets.
- `sections.json` — logical sections with page ranges, heading ancestry, section type, extraction eligibility.
- `metadata.json` — candidate and selected metadata values with evidence and validation status.
- `claims.json` — extracted facts before reconciliation.
- `verified_claims.json` — claim support status and verifier notes.
- `review_artifact.json` — final candidate view for human review/import.

### Field-level evidence shape

```json
{
  "field": "hosts.scientific_name",
  "value": "Quercus alba",
  "raw_value": "Q. alba",
  "confidence": 0.86,
  "support_status": "supported",
  "evidence": [
    {
      "artifact": "normalized_text.jsonl",
      "page": 12,
      "block_id": "p12-b04",
      "char_start": 188,
      "char_end": 202,
      "quote": "on Q. alba"
    }
  ],
  "uncertainty_reasons": []
}
```

### Association-level shape

```json
{
  "association_id": "assoc_001",
  "gall_maker": {
    "scientific_name": "Andricus quercuscalifornicus",
    "name_as_written": "Andricus quercus-californicus",
    "authority": null,
    "rank": "species",
    "taxonomy": { "order": "Hymenoptera", "family": "Cynipidae" },
    "aliases": [],
    "common_names": []
  },
  "hosts": [
    {
      "scientific_name": "Quercus agrifolia",
      "name_as_written": "Quercus agrifolia",
      "normalization_status": "candidate_match",
      "evidence": ["ev_host_001"]
    }
  ],
  "gall_traits": {
    "plant_part": {
      "original": "on the midrib of the leaf",
      "suggested": ["leaf midrib"],
      "evidence": ["ev_trait_001"]
    },
    "shape": {
      "original": "globular",
      "suggested": ["globular"],
      "evidence": ["ev_trait_002"]
    }
  },
  "warnings": [],
  "confidence_bucket": "medium"
}
```

## Prompting Strategy

Decomposed prompts, not one big document prompt.

Prompt families: metadata extraction & reconciliation; section classification; candidate gall/host span detection; entity extraction; association extraction; gall trait extraction; controlled vocabulary mapping; evidence verification; reconciliation/conflict summarization.

Cross-cutting rules:

- Extract only from the provided text.
- Prefer null or empty arrays over guessing.
- Quote exact supporting text for every nontrivial value.
- Keep `name_as_written` separate from normalized names.
- Treat old synonyms and uncertain identifications as source claims, not accepted taxonomy.
- Split multiple hosts, gall forms, alternate generations, or gall-makers into separate candidate associations when text supports separation.
- **Do not extract adult gall-maker traits as gall traits.** (Inline the disallowed trait list.)
- Do not infer host association from proximity alone; require wording, table structure, heading context, or an explicit relationship.

Use structured outputs where supported (DeepInfra and OpenRouter both expose JSON-schema response formats for many models). Always keep schema validation and retry/repair around the model — provider/model support varies.

**Self-consistency selectively, not by default.** Multi-pass extraction on every section wastes money. Use it for low-confidence, high-value, or conflict-heavy sections, plus on Stage 8 (candidate detection) where recall matters most. Reconcile by evidence agreement, not raw majority vote.

## OCR & Text Extraction

The text layer is the foundation. A strong LLM cannot reliably repair an extraction layer that loses page structure, table rows, or species headings.

**Born-digital PDFs**: PyMuPDF or `pypdfium2`. Extract page blocks (and words if needed). Detect two-column / table-like layout problems with simple quality checks.

**Scanned pages**: Render flagged pages to images; OCR page-by-page; cache by page-image hash. Local OCR for easy scans (Tesseract via OCRmyPDF). For degraded pages, route to a provider model (Mistral OCR via API, or Nougat-base / RolmOCR-7B on DeepInfra). Store OCR method/model + per-character confidence.

**Quality signals** (per page): text characters, weird-character ratio, missing-space / excessive-line-break indicators, repeated header/footer frequency, very-short-line proportion, scientific-name damage patterns, page-image coverage, table/column risk.

For BHL or similar sources, prefer source-provided OCR when available; compare against local/provider OCR; keep the best per page but preserve alternatives when quality differs.

## Validation & Uncertainty

Layered validation:

- **Shape**: JSON Schema.
- **Field**: DOI format, year ranges, page ranges, required evidence IDs, **quote text actually present in the referenced artifact** (RapidFuzz `partial_ratio >= 90`). This is a hard gate — fields whose quote isn't in the text are nulled.
- **Domain**: hosts must be plant taxa; gall-maker / host roles not swapped; gall traits use gall-description language.
- **Section**: facts from references / bibliography / unrelated captions are rejected or heavily downgraded.
- **Evidence verification**: separate-model verifier confirms support per claim.
- **Normalization**: name matches against local data and GBIF / Catalogue of Life are *suggestions*, never silent rewrites. Never let the LLM emit a name that doesn't appear verbatim in the source text.

Uncertainty fields per claim:

- `confidence_bucket`: `high` / `medium` / `low`
- `evidence_strength`: `direct_quote` / `table_row` / `heading_context` / `inferred` / `unsupported`
- `uncertainty_reasons`: OCR damage, ambiguous host, old synonym, conflicting mentions, table parse risk, chunk boundary, missing gall-maker, suspected adult-trait leakage
- `conflicts`: competing values + their evidence
- `review_action`: `preselect` / `require_choice` / `possible_mention` / `discard`

### Triage thresholds (concrete)

A field-claim is **auto-accepted** only when *all* hold:

- `evidence_strength` is `direct_quote` and verifier returns `supported`
- OCR confidence on the supporting span ≥ 0.95 (or page is digital-native)
- Sample agreement on the value (where k-sampling was run) is unanimous
- For scientific names: exact match to GBIF or Catalogue of Life
- The field is not in the **high-stakes-on-first-appearance** list (host species and scientific names always go to review on first appearance for a given species; once a human confirms, subsequent identical claims may be auto-accepted)

A claim goes to **needs_review** if at least one signal is high but it doesn't clear auto-accept.

A claim is **rejected** (logged, not surfaced) if no signal clears the minimum bar, or if Stage 8 (candidate) and Stage 9 (extraction) disagree about whether a gall is being described.

## Human Review Boundary

The pipeline proposes evidence-backed claims. Humans approve database changes.

Reviewer actions:

- accept fact as-is
- edit value while preserving or replacing evidence
- reject fact with reason
- mark not enough evidence
- resolve entity to existing Gallformers record
- create candidate new source/species/host through normal domain workflows
- approve metadata separately from biological facts

Reviewer decisions feed evaluation data; they do not become hidden prompt tweaks embedded in UI behavior.

## Evaluation Plan

**Build the gold corpus before tuning prompts or choosing a default model.**

Initial corpus (30+ documents):

- 10 modern born-digital PDFs
- 10 scanned old journal articles
- 5 table-heavy papers
- 5 long monographs / taxonomic treatments
- Include hard cases: OCR-damaged names, synonyms, unnamed gall-makers, multiple hosts, alternate generations, plate captions, keys, papers with extensive adult morphology

Gold labels: document metadata; gall-maker names + names as written; aliases / common names; host names + associations; taxonomic context; gall traits only; evidence quote / page / span; facts to abstain from; adult-trait false-positive traps.

Metrics:

- metadata exact + normalized accuracy
- association precision / recall / F1
- host precision / recall
- gall trait precision / recall by field
- evidence support rate
- unsupported / hallucinated fact rate
- abstention quality
- **gall-vs-maker confusion rate** (the failure mode that most threatens data quality)
- reviewer edit / rejection rate
- cost per document and per page
- wall-clock time per document
- **calibration**: reliability diagram of (predicted confidence) vs (empirical accuracy). **Calibration drift is a release gate** — never deploy a change that worsens calibration even if mean accuracy improves.

Bakeoffs run against the same artifacts and gold labels. Prefer the model/config with the best evidence-supported precision at acceptable recall and cost — not the one that extracts the most facts.

## Cost & Operations

Operational model:

- Elixir starts Oban jobs.
- Jobs invoke Python CLIs / subprocesses for PDF/OCR tooling.
- LLM calls go through provider adapters.
- **No persistent Python web service for v1.**
- Low default concurrency; per-provider rate limits.
- Stage-level timeouts and retries.
- Cache everything expensive by content/config hash.

Cache keys:

- PDF SHA-256
- page image hash (for OCR)
- stage input hash
- stage config hash
- prompt version
- schema version
- provider + model ID
- section hash

Tier model usage:

- **Cheap or deterministic**: profiling, cleanup, sectionization, DOI extraction, simple candidate detection.
- **Stronger text models** (Llama-3.3-70B-Instruct, Qwen2.5-72B-Instruct on DeepInfra as starting defaults): dense biological extraction (Stage 9).
- **Vision/OCR models**: only on pages requiring OCR.
- **Different-family verifier** (DeepSeek-V3 or a Claude Haiku-class model via OpenRouter): independent verification (Stage 10).
- **Frontier models** (Claude Sonnet via OpenRouter): only if gold-set evaluation shows open-weights failing. Decide based on measurement, not vibes.

### Target cost (anchoring, to be confirmed by measurement)

Per paper: ~$0.02 digital, ~$0.05 with OCR. Per 1000 papers: ~$30 at a 70/30 modern/scan mix. If Stage 9 escalates to Claude Sonnet, per-paper jumps ~10× to $0.13–$0.20 — still trivial at scale. **Idle cost: $0/mo for ML** (DeepInfra/OpenRouter are pay-per-token; no persistent service).

Confirm or revise these numbers with a measured run on the 30-paper gold set before committing to defaults.

## Failure Modes

Primary risks:

- OCR corrupts scientific names; LLM "helpfully" corrects to a similar-looking valid species.
- Two-column pages or tables merge unrelated text.
- References get mistaken for source facts.
- Plate captions duplicate or contradict main descriptions.
- LLM invents host associations from nearby names.
- Adult gall-maker morphology extracted as gall morphology.
- Multiple hosts or gall forms collapsed into one record.
- Old synonyms treated as accepted names too early.
- Long monographs exceed context and lose section context.
- Evidence snippets are plausible but not exact source text.
- Provider/model behavior changes over time (silent regressions).
- **Schema drift**: Elixir trait enums add a value, the prompt's enum list goes stale, the model emits values silently dropped by the validator.

Mitigations (all mapped to specific stages above):

- Page-level extraction quality scoring (Stage 2).
- OCR only where needed, with per-page caching (Stage 4).
- Raw + normalized artifacts with span maps (Stages 3 & 5).
- Section-aware chunking and reference-section exclusion (Stage 6).
- Table-specific extraction path (Stage 9).
- Closed-set evidence span citations (Stage 9).
- Substring verification gate (Stage 10).
- Independent different-model verifier (Stage 10).
- Strict schema validation and quote-presence checks (Stage 11).
- Preserve `name_as_written`; never auto-rewrite (Stage 11).
- Conflict reporting instead of silent merging (Stage 11).
- Prompt / schema / model versioning recorded per run (manifest).
- Evaluation gates (calibration + gold set) before changing defaults.
- **CI guard**: generate Pydantic schemas and prompt enum lists at build time from a single source of truth (export Elixir enums to JSON in CI; Python loads it). CI test fails if any enum drifts.

## Phased Implementation

**Phase 1 — Contracts & gold set**
- Define artifact manifest and JSON schemas.
- Define evidence/span model.
- Build the initial 30-document gold corpus.
- Write evaluation metrics and calibration measurement *before* prompt tuning.

**Phase 2 — Reliable text layer**
- Document profiling.
- Per-page native extraction.
- Scanned-page OCR fallback (start local, add provider fallback).
- Raw + normalized text artifacts with transform map.
- Quality reports.

**Phase 3 — Metadata extraction**
- Deterministic DOI/title/year/journal extraction.
- LLM fill-in and reconciliation (cheap model).
- Evidence-backed metadata fields.
- Optional Crossref / source-API verification.

**Phase 4 — Sectionization & candidate detection**
- Section classifier (rule-based first).
- Detect species treatments, host lists, descriptions, tables.
- Exclude references by default.
- Inspectable candidate windows.

**Phase 5 — Evidence-backed fact extraction (v1 ship target)**
- Focused prompts for entities, associations, gall traits.
- Constrained structured output + schema validation.
- Evidence required per field; closed-set span citations.
- Adult-trait contamination checks (both prompt-side exclusion list AND a check in normalize_and_reconcile).
- **v1 scope**: digital PDFs only, ~5 trait fields (scientific name, host species, gall plant_part, color, season). Hardcoded model defaults. No OCR. Staging table only — no auto-promote.

**Phase 6 — Verification & reconciliation**
- Independent claim verification (different-family model).
- Deterministic merge / dedupe.
- Host and gall-maker normalization suggestions.
- Controlled trait vocabulary mapping.
- Conflicts and warnings emitted.

**Phase 7 — Review artifact integration**
- Review-ready artifacts.
- Review UI independent from pipeline semantics.
- Reviewer decisions recorded as evaluation/training signals.

**Phase 8 — Operational hardening**
- Provider fallback.
- Cost and latency reporting.
- Admin controls for re-running selected stages.
- Regression reports for model/prompt/schema changes.
- Schema-drift CI guard wired in.

## Open Questions

- Which source classes matter most initially: BHL scans, recent journal PDFs, or known high-value monographs?
- What controlled vocabulary should gall traits map to first? (Blocked on a pass through `lib/gallformers/galls/gall_traits.ex` and `filter_fields.ex`.)
- Which external taxonomic services are authoritative for gall-makers vs host plants? (GBIF? Catalogue of Life? Both with precedence rules?)
- How much imperfect recall is acceptable if precision and evidence quality are high?
- Should source-provided OCR be trusted over local/provider OCR, or chosen per-page by quality score?
- What's the maximum acceptable cost per paper for first-pass extraction? (Anchor: ~$0.05; needs confirmation.)
- Is Stage 9 evidence-pack assembly (per-species deterministic retrieval before extraction) required for v1, or is per-section chunking adequate? (Plan2 argued strongly for per-species packs as the biggest quality lever.)

## Verified External Capability Notes

- DeepInfra structured outputs: https://docs.deepinfra.com/chat/structured-outputs
- OpenRouter structured outputs: https://openrouter.ai/docs/features/structured-outputs
- Crossref REST API: https://www.crossref.org/documentation/retrieve-metadata/rest-api/
- BHL page metadata/OCR endpoints: https://www.biodiversitylibrary.org/docs/api3/GetPageMetadata.html
- PyMuPDF: https://pymupdf.readthedocs.io/
- OCRmyPDF: https://ocrmypdf.readthedocs.io/

## Relationship to existing matters

- **7c2b** (Decompose data_extract into multi-pass extraction pipeline) — narrower; addresses the current single-call extraction stage. This matter (greenfield synthesis) supersedes 7c2b's scope if pursued. Decide whether to retire 7c2b or keep it as the incremental path.
