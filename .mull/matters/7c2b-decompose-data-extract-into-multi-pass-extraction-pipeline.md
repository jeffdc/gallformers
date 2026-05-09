---
status: planned
created: 2026-05-09
updated: 2026-05-09
epic: source-ingestion
---

# Decompose data_extract into multi-pass extraction pipeline

Problem

The current ingestion pipeline asks the data extraction stage to do too many jobs in one LLM call: discover gall-host associations, correct obvious OCR-damaged taxonomic names when extracting taxonomy, normalize taxonomy, extract raw morphology, map traits to the controlled vocabulary, infer fields like form and detachable, and assign confidence. In practice this tends to preserve the easiest fields (gall species, host species) while missing or under-extracting the trait data.

Relevant current implementation:
- lib/gallformers/ingestion_pipeline/stages/data_extract.ex
- priv/prompts/data_extract.txt
- lib/gallformers/ingestion_pipeline/schema.ex

Why the current shape is fragile

- The prompt is overloaded. It mixes recall-heavy information extraction with normalization and inference.
- The stage currently chunks cleaned text at 3,000 characters by default. Morphological description can be separated from the main taxon/host mention, so a single chunk may not contain all context needed for accurate trait extraction.
- Trait extraction has a higher attentional cost than species/host extraction. In a single-pass prompt the model can satisfy the schema with the easy fields and omit or thin out the morphology.
- Hallucination pressure is higher because the model is also asked to correct obvious OCR-damaged taxonomic names, fill taxonomy gaps, and infer controlled-vocabulary values in the same response.

Design basis

This should be designed around extraction patterns that generally work well with LLMs, not around one representative paper.

Principles:
- Decompose the task into narrow passes with one main objective each.
- Preserve evidence before normalization or inference.
- Use focused context windows instead of asking the model to reason over a whole document or arbitrary fixed-size chunks.
- Keep controlled-vocabulary mapping separate from raw evidence extraction.
- Prefer deterministic code for repeatable transformations and schema enforcement.
- Treat source structure such as headings, tables, captions, and entry numbering as optional signals, not assumptions.

Decision

Replace the single-pass data_extract design with a multi-pass extraction pipeline. This is not gated on a bakeoff. The current approach is not tenable for production ingestion because it loses too much trait information and makes failures hard to diagnose.

Use three logical passes:

1. Discovery pass
- Goal: maximize recall of gall-host associations and candidate gall entries.
- Input: cleaned text from llm_clean segmented into deterministic text units, such as paragraphs, headings, tables, and captions.
- Output: lightweight association candidates with gall species name, host species name, candidate entry id, any explicit source-structure context, confidence, and evidence anchors back into the cleaned text.
- Keep this pass narrow. Do not ask it to produce final trait mappings.

2. Trait extraction pass
- Goal: extract raw descriptive evidence for each discovered association or candidate entry.
- Input: a focused local text window built from the discovery evidence anchors plus nearby relevant text units.
- Output: raw morphology and descriptive fields only: shape, color, texture, walls, cells, alignment, plant part, season, locality, detachable clues, and the full morphology description span.
- Preserve exact source phrasing where possible. This pass should prefer null/empty raw fields over invented evidence.

3. Normalization and inference pass
- Goal: convert discovery plus raw trait evidence into the final gall record contract used by the review UI.
- Map raw text to the controlled vocabulary.
- Infer form and detachable from extracted evidence.
- Normalize taxonomy and confidence.
- Prefer deterministic code for vocabulary mapping and obvious inference rules where feasible. Use an LLM only for ambiguous cases that need judgment.

Intermediate artifacts

Introduce intermediate JSON artifacts rather than only producing the final data_extract/output.json artifact.

Suggested artifacts:
- data_extract/text_units.json: deterministic index of the cleaned text, including paragraphs, headings, tables, captions, and offsets where available.
- data_extract/discovery.json: association candidates and their evidence anchors.
- data_extract/raw_traits.json: raw evidence extracted for each candidate.
- data_extract/output.json: final normalized records that conform to the existing gall_record schema.

Evidence anchors

Use a combined anchor format:
- text_unit_ids for stable reconstruction of local context windows.
- optional section_id or heading_id when a document has clear headings.
- char_start and char_end offsets within the immutable llm_clean artifact for precise highlighting when available.
- evidence_quote copied from the source text as a human-readable fallback.

Text unit ids should be generated by a deterministic segmentation pass over the cleaned text. Character offsets are useful but should not be the only anchor because future cleanup or rendering changes can make offset-only references brittle. Copied evidence quotes are not enough by themselves because repeated phrases are common in taxonomic literature.

Trait pass granularity

Run discovery over bounded text windows that preserve nearby structure, not arbitrary fixed-size chunks. For example, a discovery window can contain a heading plus several following text units, or a table plus its caption, when those structures are present.

Run trait extraction per candidate association or candidate entry, using a focused text window reconstructed from anchors. Per-candidate windows keep the model focused on morphology and reduce the chance that details from neighboring entries bleed together.

Some sources describe one gall entry with multiple hosts, or multiple gall forms on one host. The discovery pass should preserve candidate entry ids so the trait pass can reuse one raw morphology extraction across multiple association records when appropriate.

Deterministic normalization rules

Move these into code where feasible:
- Season mapping from months and phrases like present throughout the year.
- Historical plant-part synonyms such as nether surface, upper surface, costa, midrib, nervules, petiole, leaf lamina.
- Common color glossary mappings such as stramineous, castaneous, concolorous with leaf when context supports it.
- Family/order inherited from source structure only when the source explicitly groups entries by causal organism or named taxonomic group.
- Detachability rules for obvious cases: leaf rolls/folds/curls and stem or midrib swellings are integral; discrete pedunculate or lid-bearing structures are detachable; otherwise unknown.
- Form rules for obvious cases already described in the prompt: leaf margin rolls, leaf margin folds, blisters, midrib/stem swellings.
- Schema validation and contract normalization.

Keep LLM judgment for cases where morphology is sparse, ambiguous, spread across multiple text units, or described with historical terminology that cannot be mapped safely by simple rules.

Review workspace behavior

Low-confidence or conflicting outputs should not be silently collapsed. Preserve the raw evidence and surface review flags.

Suggested flags:
- missing_trait_evidence: association found, but little or no morphology extracted.
- normalization_conflict: raw evidence maps to multiple plausible vocabulary values.
- taxonomy_uncertain: gall-maker or host name required correction or was only partially identified.
- context_inherited: family/order or other taxonomy came from document structure rather than the entry itself.
- possible_duplicate: two candidates may represent the same gall-host association from repeated text, captions, tables, or illustrations.

The review UI should show the final normalized value next to the original evidence phrase and the source text window. Reviewers should be able to accept the normalized value, clear it, or replace it manually.

Fallback model path

Add a fallback model path only for targeted retries, not for every document.

Use fallback when:
- discovery finds an association but raw_traits has missing or very sparse morphology.
- normalization produces conflicts that cannot be resolved deterministically.
- the model reports low confidence but the evidence window contains descriptive text.
- JSON/schema validation fails after normal retry handling.

This keeps costs bounded while allowing stronger models to be used where they matter most.

Expected benefits

- Better trait recall because the model is no longer juggling association discovery and final-schema generation at the same time.
- Lower hallucination rate because normalization and inference are delayed until after evidence capture.
- More targeted model spend. Cheap/high-throughput models can handle discovery; stronger models can be reserved for trait extraction retries or low-confidence cases.
- Better debuggability. Failures become inspectable by pass: missed association, missing evidence, or bad normalization.
- Better reviewer UX because evidence can be shown alongside normalized values.

Implementation outline

1. Add deterministic segmentation of cleaned text into stable text units.
2. Add a discovery prompt/schema that emits lightweight candidates with evidence anchors.
3. Add a trait extraction prompt/schema that operates on candidate windows and emits raw evidence, not final normalized records.
4. Add normalization code that combines discovery plus raw traits into the existing gall_record schema.
5. Add targeted fallback retry support for sparse, conflicting, or invalid outputs.
6. Update artifacts and review workspace code to retain and expose intermediate evidence.

Implementation notes

- Preserve the existing final output contract initially so downstream assemble/upload/review behavior can migrate incrementally.
- Treat intermediate artifacts as first-class debugging artifacts. They are necessary to inspect failures without rerunning the entire pipeline.
- Use document headings only when they are present and explicit. Do not make the architecture depend on headings or any other structure from one source document.
- Model selection should be revisited after decomposition. The current all-in-one setup overstates how much model quality alone can fix the problem.

