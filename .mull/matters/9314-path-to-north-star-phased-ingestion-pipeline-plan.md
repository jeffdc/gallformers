---
status: raw
created: 2026-05-10
updated: 2026-05-15
epic: source-ingestion
relates: [4fef]
---

# Path to north star — phased ingestion pipeline plan

# Ingestion Pipeline — Path to North Star

## Context

Gallformers ingests academic papers about plant galls and extracts structured species data. The current pipeline (8 stages, single monolithic LLM extraction call against Qwen2.5-72B on DeepInfra) works well enough to feed a human-review LiveView but has structural ceilings: no evidence/citations, one prompt doing too many jobs, no verifier pass, no controlled-vocab enforcement, no OCR, no provider abstraction, hard-coded stage ordering, and no fast local iteration loop for prompt experimentation.

A greenfield design captured in mull matter `ce28` describes the **north star**: a 12-stage pipeline with per-field evidence, decomposed prompts, an independent verifier, conflict modeling, calibration, and proper OCR.

This plan **does not implement the north star directly**. It builds *towards* it in phases that each ship a real, human-testable improvement we can run on real papers and learn from. The pipeline is not in production and there are no other users; we can change the schema, throw away data, change the UI, and run experiments freely.

An existing Python harness at `services/source-ingestion/` (multi-provider YAML config, pipeline definitions with forking, per-stage resumability, OCR support, prompts for cleanup/metadata/data-extract) is more aligned with the north star than the Elixir pipeline is. Phase 0 makes it our official architectural-proof and prompt-iteration loop.

## North Star Principles

These four principles ground every decision below. If a phase or task does not advance one of these, it does not belong in this plan.

### 1. Every claim is evidence-bound

No structured field reaches the database — or even the reviewer's screen — without a character-offset citation back to the source text, programmatically verified by substring match before persistence. Citations are *selected* from a closed set provided to the model in the prompt. They are never authored or paraphrased by the model.

This is the principle most absent from the current implementation. The current schema has no evidence fields at all.

### 2. Decompose LLM work into narrow, focused passes

One job per prompt. Entity extraction, trait extraction, taxonomy normalization, and adult-trait disambiguation are different jobs and must not share a prompt. Verification is always a separate call against a different model family (so the verifier can disagree with the extractor).

The current `data_extract` stage violates this in the most damaging way possible — one 5.6KB prompt asks Qwen-72B to do all of the above plus controlled-vocab mapping plus confidence calibration. This is the central reason this work is happening.

### 3. The pipeline proposes; the human decides

Every output is a suggestion. The pipeline writes nothing into production `species`/`gall`/`host`/`alias`/`species_source` tables without explicit human approval through the review UI. There is no auto-accept threshold, no high-confidence shortcut, no batch-import bypass.

But suggestions cost reviewer time. The pipeline must abstain when uncertain rather than spam the reviewer with guesses. A field with no good evidence should be omitted, not invented.

### 4. Pluggable, configurable, fast to iterate

Models, prompts, stage ordering, heuristics, and providers must be tunable per-run via configuration — no code changes, no redeploys to swap a model or try a new prompt. The current `pipeline_configs` JSONB tunes in-stage knobs only; this needs to extend to stage ordering, prompt selection, and provider/model selection per stage.

Iteration on real papers must be fast and local. A prompt change should be testable against a known-good paper in seconds, not minutes. Slow loops kill the prompt-engineering work that quality depends on.

## Principles Considered and Set Aside

- **"Wrong data is worse than missing data"** — folded into #3. The human-approval gate makes the cost of a bad suggestion bounded; the principle survives as the abstention clause.
- **"Carry uncertainty as separate signals; conflicts first-class"** — tactical implementation of #1, not a separate principle.
- **"Cheapest model that hits the bar"** — operational discipline, not principled. Falls out of #4 (configurable models) plus measurement.
- **"Evolve from production"** — not applicable; no production users.
- **"No idle GPU"** — constraint, not principle.

## Phase Structure

Seven phases (Phase 0–6). Each ends with a state where the pipeline can be run end-to-end on a real paper and the result inspected by a human. Each phase is grounded in at least one of the four principles (noted in parentheses).

Phase 0 and Phase 1 are detailed because they are the next two we'll execute. Phases 2–6 are sketched; we'll detail them after we learn from earlier phases (per principle #4 — iterate based on what we see).

### Phase 0 — Prove the architecture in Python (P1, P2, P4)

Validate the central greenfield architectural moves on real gall papers before committing Elixir refactoring time. Elixir iteration is too expensive for design-validation; Python iteration in the existing harness is the right loop. Phase 0 ends with a working pipeline that emits the north-star review artifact contract on the iteration corpus, plus a documented head-to-head against the current monolithic baseline.

This is the single most important phase in the plan. Everything downstream rests on its findings.

#### Data flow (concrete, end to end)

```
PDF
  ↓ (existing: extract + preprocess + llm-clean)
cleaned_markdown.txt (one string)

  ↓ (NEW: sectionize.py — rule-based)
sections.json:
  [{section_id, type, char_start, char_end, heading_path,
    extraction_eligible: bool}]
  // "references" / "bibliography" / "literature_cited" → extraction_eligible: false

  ↓ (NEW: chunks.py — deterministic, only over extraction_eligible sections)
chunks.json:
  [{span_id: "S_0001", section_id, page, char_start, char_end, text}, ...]
chunked_input.txt:
  "[S_0001] First paragraph text...\n\n[S_0002] Second paragraph..."

  ↓ (NEW: find_candidates.py — LLM, cheap, N=3 self-consistency, union then ≥2-of-3)
  // Input prompt sees chunked_input.txt
candidates.json:
  [{candidate_id: "C_001",
    gall_maker_mention: "Andricus quercuscalifornicus",
    mention_span_ids: ["S_0033", "S_0034"]}, ...]

  ↓ (NEW: evidence_pack.py — DETERMINISTIC, no LLM, per candidate)
  // For each candidate: take mention_span_ids + N spans before/after each
  // (N=2 by default), dedupe, sort by span_id
for each candidate_id, produces:
  evidence_pack_C001.txt:
    "[S_0031] ...\n[S_0032] ...\n[S_0033] ...\n[S_0034] ...\n[S_0035] ..."
  evidence_pack_C001.meta.json:
    {allowed_span_ids: ["S_0031", "S_0032", "S_0033", "S_0034", "S_0035"]}

  ↓ (NEW: extract_facts.py — LLM, per candidate)
  // Prompt input:
  //   - candidate.gall_maker_mention
  //   - evidence_pack_C001.txt (the numbered spans)
  //   - explicit list of allowed_span_ids
  //   - adult-trait exclusion list
  //   - controlled vocab
  //   - few-shot with gall-vs-maker contrast example
  // Output JSON schema:
  //   - every leaf field is {value, raw_value?, evidence: [{span_id, quote}], confidence}
  //   - evidence_span_ids constrained to allowed_span_ids via JSON-schema `enum` per item
facts_C001.json:
  {gall_maker: {
     scientific_name: {value: "Andricus quercuscalifornicus",
                       name_as_written: "Andricus quercus-californicus",
                       evidence: [{span_id: "S_0034", quote: "Andricus quercus-californicus"}],
                       confidence: 0.85},
     authority: {value: null},
     ...},
   hosts: [{scientific_name: {value: "Quercus agrifolia",
                              name_as_written: "Quercus agrifolia",
                              evidence: [{span_id: "S_0035", quote: "on Q. agrifolia"}],
                              confidence: 0.9}}],
   gall_traits: {color: {original: "bright red",
                         suggested: ["red"],
                         evidence: [{span_id: "S_0035", quote: "bright red galls"}],
                         confidence: 0.8},
                 ...}}

  ↓ (NEW: verify.py — DETERMINISTIC substring gate, per field, no LLM)
  // For each leaf field's evidence[].quote:
  //   1. Look up evidence.span_id → chunks.json[span_id].text
  //   2. Run rapidfuzz.fuzz.partial_ratio(quote, span.text)
  //   3. If < 90: null the field, append warning {field, span_id, quote, span_text, ratio}
  //   4. If ≥ 90: find the substring position in span.text;
  //      enrich evidence with {page, char_start, char_end} (absolute, not span-relative)
gated_facts_C001.json:
  // Same shape as facts_C001.json but fields whose quote didn't match are nulled,
  // and surviving fields have full char_start/char_end populated.

  ↓ (NEW: verify_claims.py — LLM, DIFFERENT MODEL FAMILY, per surviving field)
  // Per-field input (NO original prompt context, NO neighbor spans):
  //   {field_name, claim_value, quoted_span_text}
  // Output: {support_status: supported|contradicted|not_enough_evidence|needs_human_review,
  //          reason: short string}
verified_facts_C001.json:
  // Each surviving field gets support_status + verifier reason attached.

  ↓ (NEW: assemble_review.py — deterministic)
review_artifact.json:
  {document_metadata: {...},
   gall_records: [<one per candidate, drawn from verified_facts>],
   manifest: {model_versions, prompt_hashes, seed, costs, timing, warnings[]}}
```

**Key concepts to internalize:**

- A **span** is a numbered paragraph-sized chunk of source text, addressable by `span_id`. It's the smallest unit of evidence the pipeline reasons about.
- The model never invents `span_id`s — they're literals from the prompt, and the JSON schema constrains output to that closed set via per-item `enum`.
- The model **does** author the `quote` (the specific phrase within the span it relied on). The substring gate (deterministic) verifies the quote is actually present in the resolved span text. This is what makes the gate meaningful: a closed-set `span_id` alone tells you the model picked a real paragraph, but not whether the field is supported by anything in that paragraph.
- **Evidence is two-layered**: `{span_id, quote}`. `span_id` is the coarse pointer (closed set); `quote` is the fine-grained substring (verified by the gate). After the gate runs, the evidence is enriched with absolute char offsets in the source document.
- The verifier sees **only** the claim and the resolved span text — no original prompt, no other fields, no neighbor spans. This is what gives the verifier the power to disagree with the extractor.

#### What Phase 0 must validate (all from `ce28`)

1. **Evidence-bound extraction with closed-set citations** — closed-set numbered span IDs in input, `evidence_span_ids` constrained output (model can only *select*, never invent), post-hoc substring verification gate that nulls unsupported fields.
2. **Decomposed pipeline** — `find_candidate_spans` → `extract_facts` → `verify_claims`, one job per prompt.
3. **Different-family verifier** — verifier model from a different family than the extractor; returns four-value vocabulary `supported / contradicted / not_enough_evidence / needs_human_review`; sees only the claim and quoted span, not the original prompt.
4. **Self-consistency at N=3 on `find_candidate_spans` only** — high-recall step where it earns its cost; not used elsewhere.
5. **Adult-trait exclusion** — extraction prompt inlines the disallowed-trait list (antennae, wings, mesosoma, genitalia, body color, larval morphology, behavior).
6. **Bibliography exclusion via rule-based sectionizer** — references / bibliography / literature-cited sections never reach extraction.
7. **`name_as_written` preservation** — schema stores both the source string and any normalized form; pipeline never silently rewrites OCR-damaged names.
8. **Per-field provenance and uncertainty** — every leaf field carries `{value, evidence: [{page, char_start, char_end, quote}], support_status, confidence}`.
9. **Suggestion-only normalization** — controlled-vocab trait mapping returns `{original, suggested[]}`; scientific-name lookups against GBIF/Catalogue of Life return match status, not silent rewrites. (GBIF lookup may be stubbed for Phase 0; the schema must accommodate it.)
10. **North-star review artifact contract** — pipeline emits a `review_artifact.json` matching the shape defined in `ce28` (document_metadata + gall_records[] + manifest with model versions / prompt hashes / costs).

#### Iteration corpus

Commit 5 papers under `services/source-ingestion/test-corpus/`:
- 2 modern born-digital PDFs — one easy taxonomic treatment (1–2 species), one harder paper with multiple species and tables
- 2 scanned old journal articles — one BHL-clean (already-OCR'd), one degraded
- 1 paper with a long references section (target: bibliography exclusion validation)

These remain the iteration set through Phases 0–3.

#### Tasks

Tasks are ordered to match the data flow. Each names files to create, the inputs/outputs, and the role (deterministic vs LLM).

1. **Harness sanity** — `uv sync` in `services/source-ingestion/`. Run an existing pipeline config against one known PDF. Confirm it produces output. Note any breakage to triage.

2. **Iteration corpus** — Commit 5 papers under `services/source-ingestion/test-corpus/`, each in its own subdirectory with the PDF and a `notes.md` describing the paper:
   - `born-digital-easy/` — modern PDF, 1–2 species
   - `born-digital-hard/` — modern PDF, multiple species, tables
   - `scanned-clean/` — BHL-quality scan
   - `scanned-degraded/` — old scan with OCR damage
   - `refs-heavy/` — paper with a long references section

3. **Baseline run** — Run the existing monolithic-extraction pipeline (`pipelines/bhl-qwen72b.yaml` or equivalent) on all 5 corpus papers. Archive results as `output/baseline-{paper_id}/`.

4. **Export Gallformers controlled vocab** — One-time export from `lib/gallformers/galls/gall_traits.ex` and `lib/gallformers/filter_fields.ex` into `services/source-ingestion/schemas/gallformers-vocab.json`. Trait enums: color, shape, texture, walls, cells, alignment, plant_part, form, season. Hand-derived for Phase 0; Phase 3 (config) revisits this with build-time generation.

5. **Schemas** — `services/source-ingestion/schemas/`. JSON Schema 2020-12 for every artifact produced from sections.json onward. Files:
   - `sections.schema.json`, `chunks.schema.json`, `candidates.schema.json`
   - `evidence_pack_meta.schema.json` (allowed_span_ids list)
   - `facts.schema.json` — gall record; per-leaf-field `{value, raw_value?, evidence: [{span_id, quote, page?, char_start?, char_end?}], confidence}`; gall_maker `{scientific_name, name_as_written, authority?, rank?, taxonomy{}, aliases[], common_names[]}`; hosts[]; gall_traits with `{original, suggested[], evidence[]}` per trait; trait `suggested` items constrained to `gallformers-vocab.json` enums.
   - `verified_facts.schema.json` (facts + per-field `support_status` + verifier reason)
   - `review_artifact.schema.json` — `{document_metadata, gall_records[], manifest{model_versions, prompt_hashes, seed, costs, timing, warnings[]}}`
   - **Critical constraint**: each per-field `evidence_pack.meta.allowed_span_ids` is the closed set that `extract_facts`'s output must cite from. This constraint is enforced per-item via JSON-schema `enum` in the dynamically-built schema passed to the model's `response_format`. See task 9.

6. **Sectionize** — `src/ingest/sectionize.py`. Rule-based, no LLM.
   - Input: cleaned markdown (from existing `llm-clean` stage output).
   - Output: `sections.json` matching `sections.schema.json`. Types: `title, abstract, introduction, methods, taxonomic_treatment, description, host_list, key, table, references, appendix, unknown`.
   - Detection: regex on common heading patterns (`^##? (References|Literature Cited|Bibliography)\b`, `^##? Description\b`, etc.) + positional fallback for unheaded sections.
   - **References / bibliography / literature_cited → `extraction_eligible: false`**.

7. **Chunk by numbered span** — `src/ingest/chunks.py`. Deterministic, no LLM.
   - Input: cleaned markdown + sections.json.
   - Outputs:
     - `chunks.json`: `[{span_id, section_id, page, char_start, char_end, text}]`. `span_id` format: `"S_NNNN"` zero-padded. Page best-effort from existing `<!-- page N -->` markers.
     - `chunked_input.txt`: human/LLM-readable concatenation `[S_0001] ...\n\n[S_0002] ...`. **Only includes spans from `extraction_eligible: true` sections** — references are physically absent from this artifact.
   - Chunks are paragraph-bounded; one span per paragraph (or per logical block).

8. **find_candidates** — Prompt `prompts/find-candidates.md` + module `src/ingest/find_candidates.py`. LLM, cheap model.
   - Input: `chunked_input.txt`.
   - Prompt: "Identify every named gall-maker mentioned in the document. Return high-recall — include uncertain candidates. For each, list which `S_NNNN` span ids mention it."
   - Output JSON schema: `[{candidate_id, gall_maker_mention, mention_span_ids: [S_xxx]}]`. `mention_span_ids` constrained via per-item `enum` to all span_ids present in the input.
   - **Self-consistency at N=3** — call 3 times, union by normalized `gall_maker_mention` (lowercase, strip punctuation), keep candidates appearing in ≥2 of 3 samples. Implement the N-sample helper in `src/ingest/llm.py`.
   - Model: Llama-3.1-8B-Instruct via DeepInfra.

9. **Evidence pack builder** — `src/ingest/evidence_pack.py`. **Deterministic, no LLM, per candidate.** This is the bridge that was missing in the previous draft.
   - Input: `candidates.json` + `chunks.json` + `context_window` param (default 2).
   - For each candidate: take `mention_span_ids`, expand to include `context_window` spans before and after each mentioned span (within the same section), dedupe, sort.
   - Outputs per candidate (`{candidate_id}` is `C_001`, `C_002`, etc.):
     - `evidence_pack_{candidate_id}.txt`: numbered spans formatted as `[S_0033] ...\n[S_0034] ...`
     - `evidence_pack_{candidate_id}.meta.json`: `{candidate_id, gall_maker_mention, allowed_span_ids: [list]}` matching `evidence_pack_meta.schema.json`.
   - **The `allowed_span_ids` list is the closed set the extract_facts model can cite from for this candidate.** Computed deterministically, not by the model.

10. **extract_facts** — Prompt `prompts/extract-facts.md` + module `src/ingest/extract_facts.py`. LLM, one call per candidate.
    - Input per call:
      - `candidate.gall_maker_mention`
      - `evidence_pack_{candidate_id}.txt`
      - `allowed_span_ids` (inlined into prompt as a literal list)
    - Prompt content (template):
      - Closed-set citation rule: "Every `evidence.span_id` MUST be from this exact list: [S_xxx, S_yyy, ...]. The `quote` is the specific phrase from within that span that supports the field."
      - **Adult-trait exclusion list inline**: "Do NOT extract these as gall traits unless used as taxonomic context: antennae, wings, mesosoma, genitalia, body color of the adult insect, larval morphology, adult behavior."
      - Controlled-vocab references from `gallformers-vocab.json`.
      - Few-shot examples: at least one gall-vs-gall-maker contrast ("wasp has reddish antennae" → exclude), one OCR-damaged-name preservation ("Andricus quercus-cαlifornicus" → preserve in `name_as_written`, set `value` to the corrected form only if certain, else null), one host-from-table extraction.
      - Abstention rule: "Set `value` to null with `evidence: []` when the source doesn't state the field. Don't guess."
    - Output JSON schema: matches `facts.schema.json`, with **per-item enum constraint** on each `evidence.span_id` against `allowed_span_ids`. Build the schema dynamically per call so the enum reflects the actual allowed list; pass via `response_format: {type: "json_schema", json_schema: {...}}` where the provider supports it. Fall back to schema validation + retry/repair otherwise.
    - Output: `facts_{candidate_id}.json` per candidate.
    - Model: Qwen2.5-72B-Instruct via DeepInfra (matches current Elixir baseline — clean apples-to-apples comparison).

11. **Substring verification gate** — `src/ingest/verify.py`. **Deterministic, no LLM, per field.**
    - Input: `facts_{candidate_id}.json` + `chunks.json`.
    - For each leaf field's `evidence` array, for each `{span_id, quote}` entry:
      - Resolve `chunks.json[span_id].text` → `span_text`.
      - `score = rapidfuzz.fuzz.partial_ratio(quote, span_text)`.
      - If `score >= 90`:
        - Find the substring's location within `span_text` (use `partial_ratio_alignment` or a simple search after normalization).
        - Enrich the evidence entry: set `page = chunks.json[span_id].page`, `char_start` and `char_end` to **absolute offsets in the source document** (`chunks.json[span_id].char_start + local_offset`).
      - If `score < 90`:
        - Null `field.value`. Set `field.support_status = "evidence_substring_mismatch"`.
        - Append to top-level `warnings[]`: `{candidate_id, field_path, span_id, claimed_quote, span_text, score}`.
    - Output: `gated_facts_{candidate_id}.json`.

12. **verify_claims** — Prompt `prompts/verify-claims.md` + module `src/ingest/verify_claims.py`. LLM, **different model family** from extractor.
    - Input per call (and ONLY this):
      - `field_path` (e.g. `"gall_traits.color.value"`)
      - `claim_value`
      - `quoted_span_text` (the resolved span text, from chunks.json — NOT the model's quote)
    - Prompt: "Does the quoted span directly support the claim? Return one of: supported / contradicted / not_enough_evidence / needs_human_review, plus a one-sentence reason."
    - No original prompt context. No neighbor fields. No neighbor spans. This isolation is what gives the verifier the power to disagree.
    - Output: `verified_facts_{candidate_id}.json` — `gated_facts` enriched with per-field `support_status` and verifier `reason`.
    - Model: DeepSeek-V3 via DeepInfra. (Extractor Qwen + verifier DeepSeek = different model families.)

13. **Assemble review artifact** — `src/ingest/assemble_review.py`. Deterministic.
    - Input: existing `metadata.json` (from metadata stage) + `verified_facts_*.json` for all candidates + accumulated `warnings[]` + manifest data (model versions, prompt hashes, seeds, token counts, costs, per-stage timing).
    - **GBIF / Catalogue of Life lookup stubbed**: for every scientific_name, set `taxonomy_lookup: {status: "not_checked"}`. Schema accommodates real values for Phase 1+ to fill in.
    - Output: `review_artifact.json` matching `review_artifact.schema.json`.

14. **Pipeline config** — `services/source-ingestion/pipelines/north-star-v0.yaml`. Declares the stage chain end-to-end:
    ```
    extract → preprocess → llm-clean (Llama-8B) → sectionize → chunk →
    metadata (Llama-8B) → find_candidates (Llama-8B ×3 self-consistency) →
    evidence_pack → extract_facts (Qwen-72B, per candidate) →
    verify (substring gate) → verify_claims (DeepSeek-V3, per field) →
    assemble_review
    ```
    The existing harness supports stages that are deterministic (no model) and stages with models. The new deterministic stages (`sectionize`, `chunk`, `evidence_pack`, `verify`, `assemble_review`) need to be registered as harness step types; consult the existing `cli.py` and `pipeline.py` for how to add them.

15. **Run on corpus** — Execute `north-star-v0.yaml` against all 5 corpus papers. Archive as `output/north-star-v0-{paper_id}/`. Preserve every intermediate artifact (`chunks.json`, `candidates.json`, evidence packs, raw and gated facts, verified facts) for inspection.

16. **Comparison report** — `services/source-ingestion/docs/phase-0-comparison.md`. For each corpus paper, side-by-side: baseline gall records vs. new pipeline gall records, plus quantitative notes per failure mode listed below.

17. **Findings document** — `services/source-ingestion/docs/phase-0-findings.md`. What worked, what didn't, what surprised us, what to port to Elixir, what to revise in `ce28`. This document is the input to Phase 1.

#### Starting model choices (revise based on cost/quality during Phase 0)

| Stage | Model | Provider | Why |
|---|---|---|---|
| llm-clean | Llama-3.1-8B-Instruct | DeepInfra | Cheap text formatting |
| metadata | Llama-3.1-8B-Instruct | DeepInfra | Cheap structured extraction |
| find_candidates (×3) | Llama-3.1-8B-Instruct | DeepInfra | Cheap + high-recall |
| extract_facts | Qwen2.5-72B-Instruct | DeepInfra | Same as current Elixir baseline; clean apples-to-apples |
| verify_claims | DeepSeek-V3 | DeepInfra | **Different family** from extractor |

#### Failure modes Phase 0 must measurably address

For each paper in the corpus, the comparison report explicitly evaluates:
1. **Gall-vs-gall-maker confusion** — does the new pipeline correctly attribute traits to the gall vs. the inducer? Count occurrences in baseline vs. new.
2. **Hallucinated host associations** — does the verifier or the substring gate catch invented hosts? Compare host counts.
3. **OCR-corrupted name "correction"** — does the new pipeline preserve `name_as_written` rather than silently fixing OCR errors to similar-looking valid species? Required on the degraded scan paper.
4. **Bibliography contamination** — do species names from the references section leak into extraction? Required on the references-heavy paper.
5. **Abstention quality** — does the new pipeline omit weakly-supported fields (vs. inventing a guess)? Count fields with `support_status != supported` that were dropped.
6. **`original` + `suggested` co-presence** — for every trait field, is the source phrase preserved alongside the controlled-vocab mapping?

#### Exit criteria

- All 5 corpus papers process end-to-end through `north-star-v0.yaml` without errors
- Comparison report shows clear, eyeball-able quality improvement on the corpus
- All 6 failure modes show measurable improvement OR are explicitly logged as needing additional work
- Cost per paper documented (target: ≤ $0.05/paper for born-digital, ≤ $0.10/paper for scans; revise if these aren't realistic)
- Findings document captures decisions ready to inform Phase 1

If any of these don't hold, we revise the architectural plan in `ce28` before starting Phase 1.

#### Out of scope for Phase 0

- Any Elixir code changes
- Real GBIF / Catalogue of Life integration (stubbed; just prove the schema accommodates it)
- Crossref metadata verification (defer to a later phase)
- OCR (Phase 4)
- Per-page block IDs / bboxes (Phase 5)
- Provenance manifest hash-chain or content-addressed storage (Phase 5)
- Production data, UI work
- Cross-source conflict modeling for metadata (defer; record as competing claims if it falls out naturally, but don't build the full reconciliation logic)
- Calibration reliability diagrams (Phase 5)

### Phase 1 — Port the proven architecture to Elixir (P1, P2, P3)

Take what Phase 0 proved — the prompts, the stage decomposition, the verifier, the substring gate — and bring it into the Elixir pipeline. Throw away current ingestion data; we are the only user. Single landing, not a half-ported intermediate state, because Phase 0 validated these as a system, not piecewise.

**Elixir backend tasks:**
- **Schema migration**. Rewrite `priv/schemas/gall_record.json` and `lib/gallformers/ingestions/source_ingestion_species.ex`'s `ExtractionPayload` embedded schema to match the Phase 0 contract: per-field `{value, evidence: [{page, char_start, char_end, quote}], support_status, confidence}`; `name_as_written` on species; multi-host as a first-class array (not downstream collation); trait `suggested` enum-validated.
- **Provider abstraction in `llm_client.ex`**. Extract a behaviour for OpenAI-compatible chat-completion providers; implement DeepInfra and OpenRouter modules. Move `DEEPINFRA_API_KEY` out of the request layer into provider config. Add structured-output / `response_format` support.
- **Three new stage modules** in `lib/gallformers/ingestion_pipeline/stages/`:
  - `find_candidates.ex` — cheap model, high recall, returns candidate spans
  - `extract_facts.ex` — per-candidate, focused, closed-set `evidence_span_ids` constrained output
  - `verify_claims.ex` — different model family, claim-by-claim support classification
- **Substring verification gate**. Shared helper module; nulls fields whose evidence quote doesn't appear in the source artifact (Elixir equivalent of RapidFuzz `partial_ratio` — likely a custom port).
- **Workflow update**. Replace `data_extract` in `workflow.ex` with the new three-stage chain. Update `lifecycle.ex` retry mapping.
- **Delete superseded code**. `data_extract.ex`, `priv/prompts/data_extract.txt`, `SourceIngestionSpeciesEntries.collate_species_records` (no longer needed — multi-host comes from the LLM directly), the `assemble.ex` markdown output (or repurpose if useful).
- **Database migration**. Drop existing `source_ingestion_species` rows; new schema is incompatible and we have no production data to preserve.

**Review UI tasks (minimal — full overhaul is Phase 6):**
- Show evidence quote next to each field in the existing review LiveView
- Show verifier status badge (`supported` / `contradicted` / `not_enough_evidence`)
- These are tactical patches on the existing UI, not a redesign

**Prompt sharing.** If Phase 0 produced a sharing strategy (e.g., canonical prompts at repo root), wire the Elixir prompt loader to that path so future prompt iteration in the harness flows directly through. If Phase 0 chose to keep them separate, copy the Phase 0 prompts to `priv/prompts/` and accept manual sync.

**Human test**: pick a paper from the iteration corpus. Submit through the Elixir UI. Open the review screen. Every field has an evidence quote and a verifier badge. The Elixir pipeline output matches the Phase 0 Python harness output for the same paper.

**Out of scope**: stage configurability beyond current `pipeline_configs` (Phase 3); OCR (Phase 4); section-aware extraction (Phase 2); review UI redesign (Phase 6); per-page block IDs/bboxes (Phase 5).

**Risk**: this is the largest phase. The schema migration touches the staging row → review LiveView → live-tables writeback chain end-to-end. Mitigation: throw away current data; make the schema change atomic; don't preserve in-flight ingestions. Estimated 3–4 weeks.

### Phase 2 — Section-aware extraction (P2)

Add a rule-based `sectionize` stage between `llm_clean` and `find_candidates`. Detect references / bibliography / literature-cited sections and exclude them from extraction. Pass section-bounded chunks (taxonomic treatments, descriptions, host lists, tables) into `find_candidates` instead of arbitrary 3000-char windows.

**Human test**: process a paper with a long references section; observe that no false-positive species names are extracted from the bibliography. Run the iteration corpus; compare quality vs Phase 1.

### Phase 3 — Pluggable pipeline configuration (P4)

Extend `pipeline_configs` JSONB schema to allow per-run override of: stage ordering (with sensible defaults), per-stage model + provider, per-stage prompt path. `Workflow.next_stage/1` reads the stage list from config (falling back to the default sequence). Mirror the Python harness's pipeline-YAML capabilities in the Elixir pipeline configuration — the conceptual model has been validated in Phase 0.

**Human test**: create a pipeline config that swaps the verifier model from one family to another; re-run a paper; confirm different output without redeploy.

### Phase 4 — Real OCR for scanned papers (P3)

Add a `profile_document` stage (page count, text density per page, scan risk per page). Add a real `ocr_fallback` stage: OCRmyPDF/Tesseract for easy scans, provider vision (e.g., Mistral OCR or RolmOCR via DeepInfra/OpenRouter) for degraded pages. Per-page cache by image hash. Replace the misleading "ocr_fallback" code path in `priv/python/pdf_text_extractor.py`. Reuse the Phase 0 Python harness's OCR module (`services/source-ingestion/src/ingest/ocr.py`) as the reference implementation.

**Human test**: process a scanned old journal paper end-to-end; receive evidence quotes that actually appear on the OCR'd page.

### Phase 5 — Quality scaffolding (cross-cutting, backend-only)

A small gold set of ~10 hand-annotated papers as a sanity check on prompt/model changes. Per-page block IDs and bboxes captured during extraction so evidence can later be highlighted in a PDF preview. Cost-per-paper tracking surfaced. Provider-fallback hardening. No UI work in this phase.

**Human test**: re-run the gold set after a prompt change and see a per-paper diff report; check cost-per-paper for a real ingestion.

### Phase 6 — Review UI overhaul (beta gate)

A full pass over the reviewer experience for beta quality. Detailed scope deferred — the relevant design and implementation work is being captured in mull matter `415f` (species review workspace redesign). This phase pulls in that work and integrates it with the new evidence/verifier-aware data model from Phase 1.

The pipeline cannot go to beta until this phase is complete.

**Human test**: a beta user can submit a paper, review the extraction including per-field evidence quotes and verifier status, and approve it into the production tables without confusion or hand-holding.
