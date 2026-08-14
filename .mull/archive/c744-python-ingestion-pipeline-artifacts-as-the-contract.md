---
status: done
created: 2026-05-11
updated: 2026-05-12
epic: source-ingestion
relates: [7a83]
---

# Python ingestion pipeline: artifacts as the contract

## Context

- **A versioned bundle of artifacts is the contract** between pipeline and server. Anything that produces a valid bundle is a legitimate pipeline.
- **The Elixir server consumes the bundle** and runs the review UI on top of it. The producer can change implementations later without touching the consumer.

Relationship:
- **Builds on `ce28`** (greenfield synthesis). Keeps the 8-artifact set, evidence-bound contract, decomposed prompts, different-family verifier, substring gate.
- **Does not address beta UX.** How users invoke the pipeline (CLI, hosted, hybrid) is deliberately out of scope here; the artifact contract holds either way.

## Relationship to Gallformers internals

The pipeline does not run inside the Gallformers server and has no direct DB access. A few server-side facts shape its design:

- **WCVP is the canonical source for plant taxonomy.** Gallformers maintains a queryable WCVP copy server-side. Pipeline-side GBIF lookups for plants are *informational, not authoritative* — the server appends an authoritative WCVP entry to `taxonomy_lookups` during bundle import. Disagreements are surfaced to the reviewer, never silently resolved.
- **Gall-makers (insects, mites, fungi) are not in WCVP.** GBIF is the right source for them, both in the pipeline and on the server.
- **Trait controlled vocabulary** lives in Elixir (`gall_traits.ex`, `filter_fields.ex`). Pipeline consumes a generated JSON snapshot; CI guards drift.

## Operational model

- **Beta period:** user runs the pipeline themselves, supplies their own provider keys, pays the LLM bill directly. Provider config (which provider/model strings are allowed) is per-user. Pipeline emits a bundle for upload.
- **Future centralized hosting:** Gallformers hosts the pipeline, locks provider config server-side, owns cost accounting. This matter does not design that.

## Why Python (decision recorded)

Python is the right host language, not because it's intrinsically superior but because the **PDF + OCR + LLM ecosystem is Python-native**. Every alternative loses access to PyMuPDF, ocrmypdf, marker, docling, nougat, surya, and first-class LLM SDKs. TypeScript has thinner PDF tooling. Rust/Go have no ML ecosystem worth standing on.

Python's downsides are not load-bearing here: distribution friction is deferred (no beta UX), type safety is solved via Pydantic, the GIL is irrelevant for I/O-bound LLM streams.

## Framework foundation

Three libraries shift significant code from "we build it" to "we wire it." Adopt all three.

### 1. LiteLLM — multi-provider LLM client

[github.com/BerriAI/litellm](https://github.com/BerriAI/litellm). OpenAI-compatible interface to 100+ providers. Replaces ~80% of the planned `llm.py` rewrite.

- Multi-provider routing in one call (`completion(model="deepinfra/...", ...)` or `"openrouter/..."`)
- Native streaming with `stream=True` + `stream_options={"include_usage": true}`
- Per-call cost tracking against a built-in price table — we don't maintain our own
- Provider-quirk normalization across DeepInfra / OpenRouter / Anthropic
- Free observability hooks (Langfuse, Logfire) — defer using; know it's there
- Async via `acompletion` — chosen as the concurrency model for this pipeline (rationale below in `llm.py` section)

**Caveat:** LiteLLM has its own retry/fallback opinions. Configure it to do *zero* internal retries; our manifest accumulator owns the single-idle-retry policy. Verify the underlying `httpx` per-read timeout passes through cleanly (it does; this is how we enforce idle-gap kills).

### 2. Pydantic v2 — single source of truth for artifacts

Every artifact is a Pydantic model. JSON Schema 2020-12 generated via `Model.model_json_schema()` at build time. Models in `ingest/schemas.py`; generated JSON Schemas committed to `schemas/` for server-side consumption.

The closed-set span enum for `extract_facts` becomes trivial — build a dynamic Pydantic model per call with `Literal[*allowed_span_ids]`, pass its schema to the LLM.

### 3. Instructor — structured output with auto-retry

[github.com/jxnl/instructor](https://github.com/jxnl/instructor). Pydantic + LLM = structured output with automatic retry on schema validation failure. Composes with LiteLLM (async via `instructor.from_litellm(acompletion)`).

```python
result: FactsForCandidate = await instructor.from_litellm(acompletion).create(
    model="deepinfra/Qwen/Qwen2.5-72B-Instruct",
    response_model=FactsForCandidate,    # dynamic Pydantic model per call
    messages=[...],
    max_retries=2,
)
```

Replaces the planned `_extract_json_array` / `_extract_json` repair functions, the dynamic-schema-build code, and the retry-on-malformed-output policy.

### Hard skips (recorded so they're not revisited)

- **LangChain / LangGraph** — bloated, weekly churn, abstractions that fight the LLM
- **LlamaIndex** — RAG framework; not what we're doing
- **Prefect / Dagster** — production workflow orchestrators; massively overkill
- **DSPy** — research-coded; we want direct prompt-file iteration

### Defer-and-evaluate

- **Marker** or **Docling** — could collapse `extract` + `preprocess` into one ML-powered structured-extraction stage. Evaluate against the iteration corpus *after* the rest of the pipeline works.
- **Logfire** observability — free hook through LiteLLM; defer until we have something to debug.
- **VCR.py / pytest-recording** for LLM-call snapshots — makes prompt iteration fast and CI deterministic. Cheap to add when tests start mattering.

## Core architectural decision

Pipeline produces a versioned bundle. Server ingests the bundle, validates against schemas, renders review UI. Producer and consumer are decoupled — the artifact contract is the API.

```
PDF → [Python pipeline, all stages] → bundle.tar.gz → [Server: validate, store, enrich, review] → human approval → live tables
```

Server-side enrichment during import includes appending WCVP `taxonomy_lookups` entries for plant names.

## Text-substrate principle (no LLM rewrites)

No LLM stage modifies the text that evidence offsets address into. This is the consequence of dropping `llm-clean`:

- **Born-digital PDFs:** PyMuPDF block extraction → deterministic `preprocess` → addressable substrate. No LLM in this path.
- **Scanned PDFs:** vision-OCR model produces the canonical text in one pass (olmOCR / Mistral OCR / Claude Vision). The OCR model's output *is* the substrate — it's the same role the model already plays in any OCR pipeline. No separate cleanup stage.

This sharpens the substring gate: the text it validates against is either a faithful PyMuPDF extraction or a single OCR transcription. Evidence offsets are stable. Hallucinated cleanup edits cannot poison the substrate.

## Build approach: plumbing first, prompts second

Two distinct engineering disciplines hide inside this pipeline:
- **(a) Python plumbing** — code that orchestrates stages, validates schemas, manages streams and concurrency, threads manifests, packages bundles.
- **(b) Prompt engineering** — shaping LLM behavior at each stage so the extracted facts are actually any good.

Conflating them is the worst of both worlds. When output is bad, you're debugging three things at once (code, prompt, schema) without isolation. So:

### Phase A — build the plumbing with stub prompts

All Python work. End-to-end pipeline run produces a schema-valid `bundle.tar.gz` on the iteration corpus *even if every extracted fact is a placeholder*. The goal is mechanical correctness — the bundle validates, stages compose, streams stream, manifests accumulate, GBIF gets queried, cache works, the substring gate runs against real text. Prompt quality is irrelevant.

**Stub prompts** are minimal one-paragraph instructions: "Return a single candidate with `gall_maker_mention='PLACEHOLDER'` and `mention_span_ids=['S_0001']`." Instructor's schema enforcement guarantees a passing object. Stubs live at `prompts/stubs/{stage}.md`; production prompts live at `prompts/{stage}.md`. A stub pipeline config (`pipelines/north-star-v0-stub.yaml`) wires the stubs through for end-to-end Phase A runs.

**Mock mode option:** LiteLLM supports `mock_response=...` for zero-cost, zero-network end-to-end testing. Useful in CI but optional for Phase A development — running stubs against a real cheap model catches integration issues (provider quirks, streaming, schema-retry behavior) that mocks hide.

### Phase B — per-stage prompt iteration

Once Phase A is solid, real prompts replace stubs *one stage at a time*. Each prompt's iteration is independent of the others; this work can happen sequentially or in parallel and the prompts can even be assigned to different people. Each stage's Phase B activity is its own focused engagement against the iteration corpus — write the prompt, run the stage, inspect outputs, tweak the prompt, repeat until the quality bar holds.

Stages with Phase B prompt work:
- `find-candidates` (high-recall gall-maker detection with N=3 self-consistency)
- `extract-facts` (per-candidate, closed-set citation, adult-trait exclusion, gall-vs-maker contrast)
- `verify-claims` (per-field, isolated, four-value vocabulary)
- `metadata` (evidence-bound bibliographic extraction)

Phase B is where the quality of the system lives. Phase A makes it possible.

## Artifact contract

### Bundle contents (9 files)

```
bundle.tar.gz
├── manifest.json              # pipeline metadata, costs, warnings
├── source.pdf                 # original PDF
├── raw_text.jsonl             # one row per page block (audit)
├── normalized_text.jsonl      # cleaned blocks, with raw_block_ids[] back-ref
├── sections.json              # logical sections w/ extraction_eligible flag
├── metadata.json              # bibliographic metadata (evidence-bound)
├── claims.json                # all extracted facts pre-verification
├── verified_claims.json       # facts + verifier support_status + GBIF taxonomy_lookups
└── review_artifact.json       # consumer-facing assembled view
```

This is the `ce28` artifact set with five amendments (agreed):

1. **Dual evidence addressing.** Raw and normalized JSONL rows use block-relative offsets. Claims/verified_claims/review_artifact evidence cells carry **both** a `block_id` (back-reference to `normalized_text.jsonl`) **and** absolute char offsets into a derived flat-normalized-text view that the UI uses for rendering.
2. **Spans = normalized rows.** `chunks.json` from `9314` is unified with `normalized_text.jsonl`. Each row is a numbered span; `span_id` joins the row identifier. No separate chunks artifact.
3. **Per-candidate intermediates are scratch by default.** `9314`'s per-candidate `facts_C001.json` etc. live under `output/{src}/candidates/` for debugging but are not in the bundle by default. Top-level `claims.json` / `verified_claims.json` are the roll-ups. An `--include-candidates` flag bundles them for full-reproducibility debugging.
4. **PDF travels with the bundle.** Referenced by SHA in the manifest; bytes included for the review UI.
5. **Schema versioning is mandatory.** Every artifact top-level object carries `schema_version`. Server rejects bundles whose `review_artifact.schema_version` major doesn't match what it understands. SemVer.

### The evidence cell (repeating unit)

Every field that can affect the database has this shape:

```json
{
  "value": "Quercus alba",
  "raw_value": "Q. alba",
  "name_as_written": "Q. alba",
  "evidence": [
    {
      "block_id": "p12-b04",
      "page": 12,
      "char_start": 4188,
      "char_end": 4202,
      "quote": "on Q. alba"
    }
  ],
  "support_status": "supported",
  "confidence": 0.86
}
```

`support_status` is a closed enum: `supported`, `contradicted`, `not_enough_evidence`, `needs_human_review`, `evidence_substring_mismatch`, `abstained`.

For trait fields with controlled-vocab mapping, `value` is replaced by `{original, suggested[]}`. Everything else is the same.

### Scientific-name fields and `taxonomy_lookups`

Every scientific-name evidence cell (gall_maker.scientific_name, hosts[].scientific_name, family, genus, etc.) carries an additional `taxonomy_lookups` list. Each entry is a self-contained snapshot from one source:

```json
"taxonomy_lookups": [
  {
    "source": "GBIF",
    "status": "exact",                  // exact | fuzzy | synonym | no_match | api_error
    "match": {
      "scientific_name": "Quercus agrifolia",
      "rank": "species",
      "gbif_key": 2879294,
      "kingdom": "Plantae",
      "family": "Fagaceae",
      "canonical_name": "Quercus agrifolia",
      "accepted_name": null,            // populated when status == synonym
      "url": "https://www.gbif.org/species/2879294"
    },
    "confidence": 0.99,
    "queried_at": "2026-05-11T14:22:09Z"
  }
  // server appends a WCVP entry for plants during import
]
```

Pipeline produces one entry (GBIF). Server appends a WCVP entry for plant names during bundle import. Reviewer sees both side by side for hosts; just GBIF for gall-makers. Disagreements surface as warnings, never silent reconciliation.

### Warning taxonomy (closed enum)

All warnings carry `type`, `severity`, optional `record_id`, optional `field_path`, plus type-specific detail. Types:
- `evidence_substring_mismatch`, `verifier_contradicted`, `schema_repair_applied`
- `idle_timeout_retry`, `usage_estimated`
- `section_excluded`, `vocab_no_match`
- `taxonomy_no_match`, `taxonomy_fuzzy_match_low_confidence`, `taxonomy_api_error`
- `taxonomy_source_disagreement` (server adds this when WCVP and GBIF disagree on a plant name)

Extend the enum deliberately; UI rendering depends on it.

## Python pipeline change list

Grounded in current `services/source-ingestion/` (cli=281L, pipeline=372L, llm=482L, extract=55L, preprocess=269L, output=119L). The current pipeline emits a markdown doc with YAML frontmatter — same monolithic-extraction shape as the Elixir pipeline. Nothing in the current data shape can be retrofitted; the shape changes wholesale.

### A. Schemas (Pydantic-driven)

Single source of truth: `ingest/schemas.py` — Pydantic v2 models for every artifact in the bundle, the evidence cell, the warning enum, the per-trait suggested-vocab shape, the manifest entries, the `TaxonomyLookup` shape and `taxonomy_lookups` list field.

Build step generates JSON Schema 2020-12 files into `schemas/` for server-side consumption (Elixir validates against them without depending on Python). One generator script; CI runs it and fails if `schemas/` drifts from the Pydantic source.

Controlled vocab is generated from Elixir at build time: a mix task exports trait enums (`gall_traits.ex`, `filter_fields.ex`) to `schemas/gallformers-vocab.json`. Same CI guard: regenerating must produce a clean diff.

### B. New modules

| Module | Type | Produces |
|---|---|---|
| `ingest/schemas.py` | Pydantic models | source-of-truth types for every artifact |
| `ingest/sectionize.py` | deterministic | `sections.json` |
| `ingest/find_candidates.py` | async LiteLLM streaming, N=3 self-consistency | per-candidate scratch |
| `ingest/evidence_pack.py` | deterministic | per-candidate context bundles (scratch) |
| `ingest/extract_facts.py` | async Instructor + LiteLLM, dynamic Pydantic schema per candidate | per-candidate scratch |
| `ingest/verify.py` | deterministic (RapidFuzz partial_ratio >= 90) | substring-gated facts |
| `ingest/verify_claims.py` | async LiteLLM, different model family, per-field isolated | verified per-candidate scratch |
| `ingest/taxonomy_lookup.py` | async HTTP to GBIF, disk-cached by (name, rank, kingdom_hint) | enriches verified facts with `taxonomy_lookups` entries |
| `ingest/assemble.py` | deterministic | `claims.json`, `verified_claims.json`, `review_artifact.json`, `manifest.json` |
| `ingest/bundle.py` | deterministic | `bundle.tar.gz`; `--include-candidates` flag bundles per-candidate scratch for debugging |
| `ingest/manifest.py` | helper | per-call cost/timing/prompt-SHA accumulator |

Note: no separate `ingest/schema.py` validator helper — Pydantic models validate themselves on construction. The artifact write path is `Model(...) → model.model_dump_json() → file`. Reads validate symmetrically.

### Stage ordering

```
extract → preprocess → sectionize → metadata → find_candidates → evidence_pack →
  extract_facts → verify → verify_claims → taxonomy_lookup → assemble → bundle
```

No `llm-clean` stage. Born-digital relies on deterministic `preprocess`; scans rely on the OCR model producing clean text (OCR variant pipeline replaces `extract` with `ocr`).

### C. Modify

**`extract.py`** — biggest single rewrite. Switch from `pymupdf4llm.to_markdown()` (single string, no structure) to PyMuPDF block-level API (`page.get_text("blocks")` or `("dict")`). Output is `raw_text.jsonl` rows with `{page, block_id, text, bbox, extractor, quality_signals}`. URL/plain-text inputs get a synthesized single-page block.

**`preprocess.py`** — keep cleanup logic (BHL boilerplate, hyphen rejoin, line rejoin, plate-page strip), rework to operate on JSONL blocks. Output is `normalized_text.jsonl` with `raw_block_ids: [...]` per row pointing back. Track which raw blocks contributed to each normalized block — per-block precision, not character-precise, sufficient for audit. This is the addressable substrate for evidence offsets in the born-digital path.

**Flat-normalized-text derivation** — concatenate `normalized_text.jsonl` rows with `\n\n`. Stored inline on `review_artifact.json` as `source.normalized_text`. Evidence absolute char offsets address into this string. Cheap; necessary for offset-based UI highlighting.

**`llm.py`** — async-first thin wrapper over LiteLLM, not a rewrite of streaming/retry/cost from scratch:

- `async def stream_completion(messages, model, *, idle_timeout=60, total_timeout=600, response_format=None) -> (content, usage, metadata)` — wraps `litellm.acompletion(stream=True, stream_options={"include_usage": True}, ...)`. Idle-gap enforced by `asyncio.wait_for(anext(stream), timeout=idle_timeout_s)` in the consumption loop; total ceiling enforced by `asyncio.wait_for` around the whole stream.
- `async def call_with_samples(messages, model, n=3)` — N concurrent streams via `asyncio.gather`.
- LiteLLM internal retries **disabled**; our policy is single retry on idle timeout with backoff, then fail (stage caching makes failure recoverable).
- Per-call manifest record: `{model, provider, prompt_sha256, input_tokens, output_tokens, cost_usd, duration_ms, idle_timeouts_hit, total_timeout_hit, usage_estimated, status}`. `cost_usd` comes from LiteLLM's `completion_cost(response)` — no per-provider rate table to maintain.
- `instructor.from_litellm(acompletion)` for structured-output stages. JSON repair / dynamic schema construction is owned by Instructor.
- Concurrency control: `asyncio.Semaphore(max_workers)` per stage, configurable via pipeline YAML. No thread pool.
- Remove `extract_data` / `DataExtractResult`. Migrate `clean_text` and `extract_metadata` to async `stream_completion` in the same change. (Then delete `clean_text` once `llm-clean` is removed from pipelines.)

**Why async (decision recorded):** the central concurrency pattern is many concurrent streams with per-stream idle-timeout enforcement (`find_candidates` ×3, `extract_facts` × candidates, `verify_claims` × fields, `taxonomy_lookup` × names). `asyncio.wait_for(anext(stream), timeout=...)` is the right primitive for that — thread-pool + watchdog equivalents are clumsier and don't compose as cleanly with cancellation. LiteLLM's `acompletion` and Instructor's async client compose without friction. The cost is that async cascades: every LLM-using or HTTP-using stage exposes an async coroutine, and `pipeline.py` becomes an async runner bridged by `asyncio.run()` from the CLI.

**`pipeline.py`** — four changes:

1. `VALID_STEPS` += `sectionize`, `find-candidates`, `extract-facts`, `verify`, `verify-claims`, `taxonomy-lookup`, `bundle`. Replace `data-extract` and `assemble` with `assemble-review`. Remove `llm-clean` from `VALID_STEPS`.
2. Per-candidate fan-out: a multi-output stage type where the step produces one file per candidate under `output/{src}/candidates/{C_xxx}/{stage}.json`. Resumability check ("all candidate outputs exist") rather than single-file existence.
3. Stage outputs that are contract artifacts are written through their Pydantic model (`Model(...).model_dump_json(...)`) which validates on construction. Pipeline fails loudly on validation failure.
4. **Async runner.** All stage handlers are `async def` coroutines for uniformity (deterministic stages contain only sync logic but still expose async entry points). `run_pipeline()` is an async coroutine. `cli.py` bridges with `asyncio.run(run_pipeline(...))` — one event loop per pipeline invocation.

**`output.py`** — replace markdown frontmatter assembly with a shim into `assemble.py`. Repurpose `write_s3` to upload the bundle (content type `application/gzip`).

**`metadata` stage — kept separate from extract_facts (decision recorded).** Bibliographic metadata is orthogonal to per-record extraction and would make the already-hard fact-extraction prompt harder if piled on top. Metadata runs as its own one-shot-per-document stage with its own `DocumentMetadata` Pydantic model via Instructor. Output is evidence-bound `{title: {value, evidence, ...}, authors: [...], ...}` with closed-set citations from the first N spans.

### D. Replace prompts

Phase A uses stub prompts (see "Build approach"). The list below is the Phase B production work — real content, iterated against the iteration corpus.

- `prompts/cleanup.md` — **delete** (no `llm-clean` stage).
- `prompts/metadata.md` — rewrite for evidence-bound output.
- `prompts/data-extract.md` — **delete** (137-line kitchen-sink prompt is exactly what `ce28` calls out as the central problem). Split into:
  - `prompts/find-candidates.md` — high-recall gall-maker mention detection over chunked input.
  - `prompts/extract-facts.md` — per-candidate, closed-set citation rule, adult-trait exclusion list inlined, controlled vocab inlined, gall-vs-maker contrast example, OCR-damaged-name preservation example, abstention rule.
  - `prompts/verify-claims.md` — per-field, isolated input (claim + quoted span text only), four-value vocabulary.

Every prompt file gets a `# version: <sha>` marker the manifest reads. Stub variants live under `prompts/stubs/`.

### E. Delete

- `prompts/data-extract.md`, `prompts/cleanup.md`
- `extract_data()`, `DataExtractResult`, `clean_text()`, `CleanupResult` from `llm.py`
- `assemble_document()` / `build_frontmatter()` from `output.py`
- Custom JSON repair helpers (`_extract_json_array`, `_extract_json`, `_find_last_complete_object`) — Instructor owns this
- Whatever Elixir code consumes the current S3 markdown-with-YAML output (investigate before deleting)

### F. Cross-cutting

- **Vocab drift CI guard.** Mix task in Elixir exports trait enums to `services/source-ingestion/schemas/gallformers-vocab.json`. CI fails if running the task changes the file.
- **JSON Schema generation CI guard.** Generator script runs `Model.model_json_schema()` for every artifact model and writes to `schemas/*.schema.json`. CI fails if running the generator changes the files.
- **Pydantic-validated artifact writes** at every stage. No separate schema-validation gate — model construction is the gate.
- **Manifest accumulator** threaded through every stage. `StageRunContext` records per-call metadata; `assemble.py` folds into `manifest.json`.
- **Bundle step** at end of every pipeline. Tarballs the 9 files. Verifies all expected artifacts present. `--include-candidates` flag bundles per-candidate scratch.

## Open questions

1. **Marker/Docling evaluation timing.** Could replace `extract` + parts of `preprocess`. Evaluate against the iteration corpus *after* the rest of the pipeline works.

## Suggested order of work

### Phase A — plumbing with stub prompts

Goal: end-to-end run produces a schema-valid `bundle.tar.gz` on the iteration corpus. Extracted facts are placeholders; the bundle validates.

1. **`ingest/schemas.py`** — Pydantic models for every artifact. Hand-construct one valid bundle in Python REPL; serialize; verify JSON Schemas generate cleanly. This is the contract.
2. **`prompts/stubs/*.md`** — minimal one-paragraph stubs for `find-candidates`, `extract-facts`, `verify-claims`, `metadata`.
3. **`pipelines/north-star-v0-stub.yaml`** — wires the stubs through. End-to-end test config for Phase A.
4. **`extract.py` rewrite + `raw_text.jsonl`** — largest single change; downstream depends on it.
5. **`preprocess.py` rewrite + `normalized_text.jsonl`** — builds on (4).
6. **`llm.py` rewrite over async LiteLLM + manifest accumulator** — touches every LLM stage; do once before adding new ones.
7. **`sectionize.py`** — deterministic, fast to land.
8. **`find_candidates.py` + `evidence_pack.py` + `extract_facts.py`** — wired with stub prompts; Instructor enforces shape.
9. **`verify.py`** — substring gate. Test against hand-crafted facts to validate algorithm correctness.
10. **`verify_claims.py`** — wired with stub prompt.
11. **`taxonomy_lookup.py`** — GBIF, cached. Test against real names from corpus.
12. **`assemble.py` + `bundle.py`** — packaging.
13. **Metadata stage** wired with stub prompt.
14. **Vocab + Pydantic-schema drift CI guards.**
15. **End-to-end run on iteration corpus** — every paper produces a schema-valid bundle. Phase A is done.

### Phase B — per-stage prompt iteration (independent)

Once Phase A is solid, replace stubs with production prompts one stage at a time. Each stage is its own focused work item; they can be done sequentially or in parallel by different people.

- `find-candidates.md` (high-recall gall-maker detection)
- `extract-facts.md` (per-candidate, closed-set citation, adult-trait exclusion, vocab mapping)
- `verify-claims.md` (per-field, isolated, four-value vocabulary)
- `metadata.md` (evidence-bound bibliographic extraction)

Each Phase B activity: write the prompt; run the stage on the iteration corpus; inspect outputs; tweak; repeat until quality bar holds. The plumbing doesn't change between iterations.

## Out of scope for this matter

- Beta UX (distribution, upload flow). Deferred deliberately; artifact contract holds regardless.
- Server-side ingestion of the bundle (Elixir consumer) including WCVP enrichment for plant names. Lives in `415f` / Phase 6 work.
- GBIF↔WCVP disagreement *resolution* on the server. Pipeline records both; server surfaces disagreements; reviewer decides. No automated reconciliation.
- OCR pipeline tuning beyond the sketch in `pipelines/north-star-v0-ocr.yaml`. Phase 4 of `9314` still applies; the artifact schema is unchanged when OCR matures.
- Marker / Docling adoption. Evaluate later against the iteration corpus.

## Artifacts produced by this design work

- `services/source-ingestion/pipelines/north-star-v0.yaml` — born-digital pipeline config (mock-up)
- `services/source-ingestion/pipelines/north-star-v0-ocr.yaml` — scanned-paper variant (mock-up)
- `services/source-ingestion/providers.example.yaml` — updated with Llama-3.1-8B-Instruct on DeepInfra plus optional OpenRouter section

## Implementation status (2026-05-12)

### Phase A — done

End-to-end bundle produces valid `bundle.tar.gz` on all four
iteration-corpus PDFs. All ten stages wire together, graceful failure
catches any LLM misbehavior without crashing the pipeline, manifest
warnings capture what went wrong.

Iteration corpus locked to four born-digital PDFs (test-corpus/, symlinks
to local Desktop sources, gitignored):

- Cook 2026 (easy, 8p) — single-species paper, fastest feedback
- Philippines BHL (45p, scanned-with-OCR'd-text-layer) — kept as a
  baseline for the future OCR pipeline; pymupdf currently reads its
  OCR overlay as if born-digital
- Nicholls 2022 (79p) — Nearctic oak gallwasps, many species
- Cuesta-Porta 2022 (92p) — Druon genus revision, dense taxonomic
  renames, the largest paper

### Key implementation departures from the original design

- **Instructor enforcement in find-candidates.** Original code used
  `json.loads` + manual Pydantic validation and silently returned `[]`
  on parse or validation failure. Switched to
  `make_instructor_client().create_with_completion(response_model=...)`
  mirroring the pattern already used in metadata/extract_facts. Per-sample
  exceptions are caught and yield empty results + error-status record so
  "one bad sample doesn't kill the batch."

- **Graceful Instructor-failure handling across all LLM stages.**
  metadata, extract_facts, verify_claims each catch exceptions, return
  an abstaining default + error-status ProviderCallRecord. Pipeline
  runner synthesizes manifest warnings from any error-status call
  (`_warning_for_error_call` in pipeline.py). ProviderCallRecord gained
  an optional `error_detail` field; WarningType gained
  `llm_output_invalid`. Schemas regenerated.

- **Stub-config model picks.** Discovered through corpus runs:
  - Llama-3.1-8B works for find-candidates only on small/medium papers
    (Cook 3K, Philippines 25K, Nicholls 58K all OK; Cuesta 76K it
    confuses the schema and emits `_LLMCandidate` as a JSON key)
  - Qwen-2.5-72B on DeepInfra is capped at **32K input tokens**, not
    its native 128K — so it can't host find-candidates for any
    long-paper inputs. Useful for metadata, extract-facts, verify-claims
    where per-call input is small.
  - Stub config now: metadata + extract-facts + verify-claims on
    Qwen-2.5-72B; find-candidates on Llama-3.1-8B.

- **Production find-candidates model: DeepSeek-V4-Flash.** Llama can't
  follow nuanced inclusion rules (consistently dropped comparison/
  reference species even with explicit prompt anti-patterns and N=3
  self-consistency — all samples agreed on the wrong answer). Switched
  to `deepseek-ai/DeepSeek-V4-Flash` on DeepInfra: 1M-token context,
  reasoning-capable, ~$0.03 per Cuesta-call at n=3. Full-corpus
  find-candidates pass costs ~$0.07.

### Phase B — in progress

- `prompts/find-candidates.md` **done** (v0.1.3). Iterated against Cook
  through 4 versions; final corpus run produces 68 distinct candidates
  across the four papers with zero manifest warnings.
- `pipelines/phase-b-find-candidates.yaml` is the iteration config: real
  find-candidates wired through DeepSeek-V4-Flash, stubs preserved for
  the other LLM stages so one prompt's quality changes don't confound
  another's signal.
- `pipelines/north-star-v0.yaml` (production) **not yet updated**;
  still references Llama-3.1-8B for find-candidates. Update once the
  remaining Phase B prompts are ready and we settle the full production
  model set.

Remaining Phase B prompts, in order of leverage:
1. `extract-facts.md` — the matter's "central problem"; produces real
   per-candidate facts. **Next.**
2. `verify-claims.md` — per-cell verifier with four-value vocabulary.
3. `metadata.md` — evidence-bound bibliographic extraction.

### Open Phase A polish (deferred, all non-blocking)

- **Sectionizer → NormalizedBlock.section_id linkage broken.** Sections
  ARE detected correctly (Cook gets sec-1 unknown + sec-2 references
  with eligible=False), but `section_id` is `None` on every block in
  `normalized_text.jsonl`. The eligibility filter at
  `pipeline.py:_eligible_blocks` uses `b.section_id` and defaults to
  True when None — so references blocks pass through to find-candidates.
  DeepSeek-V4-Flash compensates by recognizing reference-list formatting,
  but the filter itself is effectively a no-op.
- **BHL boilerplate strip rule misses real BHL output.** Philippines
  paper's first three normalized blocks are biodiversitylibrary.org URLs
  and journal portal text that should have been dropped by
  `strip_bhl_boilerplate` in preprocess.
- **Sectionizer is too conservative.** Even on born-digital papers
  (Nicholls, Cuesta) it only finds `unknown + references`. Headings
  like "Introduction", "Methods", "Discussion" aren't being detected.
  Affects evidence-pack quality once real extract-facts prompts run.
- **Production north-star-v0.yaml model set.** Update once Phase B is
  complete; record model rationale per stage in this matter at that
  time.

## Final status (2026-05-13) — closing this matter

Phase A and Phase B are complete. Production pipeline runs the four-paper
iteration corpus end-to-end with prompt-SHA-aware resumability:

| paper | pages | candidates | duration |
|---|---|---|---|
| Cook 2026 | 8 | 2 | 78 s |
| Mutun 2015 | 3 | 13 | 132 s |
| Nicholls 2022 | 79 | 13 | 317 s |
| Cuesta 2022 | 92 | 33 | 484 s |

Aggregate quality across the four-paper corpus on the final pipeline:
647 supported facts, 39 hallucinations caught by the substring gate,
4 contradictions caught by the verifier, 0 timeouts, 0 pipeline crashes.
DeepInfra cost ~$0.30–0.60 per full-corpus pass.

### Production model set

- `find-candidates`: `deepseek-ai/DeepSeek-V4-Flash` (1M context,
  reasoning, 5–19× faster than alternatives). N=3 self-consistency.
- `extract-facts`: `Qwen/Qwen3-Next-80B-A3B-Instruct` (MoE 80B/3B-active,
  ~204 output tok/sec, picked via the documented bake-off).
- `verify-claims`: `deepseek-ai/DeepSeek-V4-Flash` (different family
  from extractor per the matter's principle).
- `metadata`: `Qwen/Qwen2.5-72B-Instruct` (small per-call input fits
  the 32K DeepInfra cap; the schema isn't large enough to need the
  faster MoE model).

Concurrency at 50-wide (extract-facts and verify-claims), DeepInfra's
ceiling is 200/model/user.

### Bake-off report

`services/source-ingestion/docs/extract-facts-model-bakeoff.md` records
the model evaluation and decision rationale (Round 1: speed/reliability/
hallucination, Round 2: extraction quality with real verify-claims).

### What landed beyond the original design

- Instructor wired into find-candidates (was: silent JSON-loads + manual
  Pydantic validation, returned [] on any parse failure).
- Graceful Instructor-failure handling in every LLM stage (metadata,
  find-candidates, extract-facts, verify-claims) — exhaustion of
  Instructor retries returns an abstaining default + error-status
  ProviderCallRecord; pipeline emits a manifest warning and continues.
- Verify-claims parallelism fix: stage was structurally serial despite a
  semaphore; switched to single global asyncio.gather. 8.1× wall-clock
  improvement on Philippines (524 s → 65 s); 50-wide later took it to 22 s.
- Verify-claims species context (B fix): verifier now sees
  "candidate species: <name>" alongside field_path / claim / quote.
  Mutun supported hosts went 7/21 → 20/21 once the verifier could
  attribute claims to the right species.
- Substring-gate index keying fix: `_index_blocks` was keying
  `NormalizedBlock.block_id` (PyMuPDF page+block) but the LLM cites
  `Evidence.block_id = "S_NNNN"` (span_id). Mismatch silently failed
  every substring check.
- Sectionizer multi-section detection: detects Abstract / Introduction /
  Methods / Acknowledgements (in addition to References / Bibliography /
  Literature Cited). When publication structure is detected, pre-first-
  heading content is classified as TITLE; otherwise legacy two-section
  behavior is preserved.
- Metadata fallback window bumped 5 → 20 blocks (handles journal-banner-
  heavy front matter on Zootaxa-style monographs).
- Controlled trait vocabulary wired (vocab JSON + extract-facts prompt
  injection + cache key inclusion).
- Prompt-SHA-aware caching for all four LLM stages with composite cache
  keys. Cold-cache → warm-cache on Cook: 76 s → 1.7 s (44×).

### Iteration corpus (test-corpus/, gitignored)

- Cook 2026 — single species, 8 pages, fast feedback
- Mutun 2015 — 12 oak gallwasp species, 3 pages, info-dense
- Nicholls 2022 — 13 Nearctic gallwasps, 79 pages
- Cuesta 2022 — Druon genus revision, 92 pages, dense taxonomic renames
- Philippines (BHL) — kept as OCR-pipeline reference; not in the
  iteration set

### Follow-ups

Three deferred non-blocking polish items moved to matter `7a83`:

1. Elixir mix task for `gallformers-vocab.json` regeneration + CI
   guard (vocab JSON currently hand-curated from a one-shot SQL dump).
2. On-disk `normalized_text.jsonl` `section_id` linkage (in-memory
   correct; on-disk has `section_id: null` because JSONL is written
   pre-sectionize).
3. BHL boilerplate strip rule (current rule expects a specific
   cover-page pattern not seen in the Philippines test paper).

All other listed-out-of-scope items (OCR pipeline, Marker/Docling
evaluation, server-side ingestion, beta UX, GBIF↔WCVP resolution)
remain out of scope for the source-ingestion pipeline matter and
belong in their respective parent matters.
