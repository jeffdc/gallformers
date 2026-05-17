# Source ingestion — outstanding work

Last updated 2026-05-17 evening, after commit `e570d825` ("Add block triage, generation-aware candidate splitting, and structured evidence prose"). Everything shipped this session is no longer listed below.

## Active blockers

_(none)_

## Recall gaps in find-candidates

- **Acraspis gemula (sexgen)** unmatched on Nicholls. Pipeline emits no candidate at all for this species. Separate root cause from header injection (which was fixed). Possibly LLM detection threshold or section eligibility. Diagnose by sampling the per-sample LLM output.
- **Amphibolips spinosa (agamic)** at 73% pipe coverage on Nicholls. The single residual non-100% species after the header fix and sibling-mention sharing both shipped. Span-selection issue specific to this species, low priority.
- **Gagne 2008 Hickories mystery**: 62 of 62 species matched by name, but only 7.1% prose coverage in the May 16 baseline (not re-measured since). Unique pattern — perfect discovery, near-zero coverage. Hypothesis: paper structure has per-species spans laid out in a way `evidence-pack` can't follow. Diagnose by walking one species end-to-end (label blocks → spans → pack contents).
- **Bassettia flavipes (sexgen)** dipped to 63.9% on the most recent Nicholls run. Root cause investigated and found to be a label-data quirk (the curator stored the asexual-generation heading under the sexgen entry in gallformers), not a pipeline regression. The sibling-mention-sharing fix landed this session was the response; needs a fresh run on Nicholls to confirm it recovered the score.

## Architectural — still on the table

- **Better PDF extractor evaluation.** Pymupdf is a dumb extractor. Nougat (Meta, neural PDF→Markdown for academic papers) and GROBID (open-source, deterministic, structured TEI XML) both produce semantically classified output (sections, references, headings) and would obviate much of the noise-stripping work. Open question — not evaluated yet.
- **Phase 2 trait-tagger refactor of extract-facts.** Per `docs/phase-2-assemble-account-design.md`. The seed (`GallRecord.evidence_prose`) is in place; the full Phase 2 is to elaborate that into a `species_account` structured object (paragraph breaks, per-paragraph span IDs) and rewrite `extract-facts` to tag traits over the curated prose rather than re-extract. Drops the redundant `description`/`location` cells.
- **Phase 2 Step 3: LLM-driven assemble-account stage.** Gated on Step 2 measurement (running the pipeline against more format-diverse sources). Only worth building if specific formats systematically underperform what `evidence-pack` + sibling-mention sharing produce.
- **Adopt `concurrency.gather_bounded` in the other stages.** `extract-facts`, `verify-claims`, and `find-candidates` still open-code the `Semaphore` + `gather` pattern inline. Cleanup follow-up; low priority since they work.

## Format failures

- **Nastasi & Davis 2022 field guide** (0% in the May 16 baseline — 2 of 49 species discovered). Non-narrative format organized by host. Find-candidates prompt is tuned for taxonomic-paper prose. Needs format-aware discovery or a fallback prompt.
- **Gagne 2017 World Catalogue** (0% in baseline — discovery returns `"Cecidomyiidae"` as a single candidate). Catalog format as a structured table. Same fix class as Nastasi & Davis.
- **Felt 1917 Key** (0% in baseline — 348-page key, hundreds of species). Two distinct size failures: metadata input too big (196K tokens vs 128K context), find-candidates output cap hit. Need input-size guard + output-aware chunking by section / page range.
- **Ashmead 1896** (~0.2% in baseline) and **Kinsey 1929** (0% in baseline). Pipeline correctly extracts historical names (`Cynips erinacei`, `Andricus excavatus`); eval labels use modern accepted names (`Acraspis erinacei`, `Callirhytis excavata`). **Pipeline behavior is correct**; eval scorer is the wrong tool here. Constraint reaffirmed: preserve names as written, never substitute. Fix: scorer-side species-epithet fallback (see eval section).

## Eval scorer improvements

- **Species-epithet fallback matching.** Currently scorer requires full-binomial match. Adding epithet-only fallback would rescue Ashmead from 0.2% to honest ~17% and similar for Kinsey. The pipeline is correct on those papers; the scorer is mis-reporting.
- **Precision dimension.** Current scorer is recall-only. Doesn't distinguish "pipeline found a real species the curator skipped" (good — Wise/Prodiplosis case) from "pipeline hallucinated a candidate" (bad). At minimum, a "candidates beyond labels" counter per source.

## Pipeline hardening

- **Quieter console error output.** The error-logging traceback printing added on May 16 is correct but voluminous — `n_samples=3` × many per-candidate calls can flood the terminal buffer. Two-tier: one-line summary on stderr, full tracebacks to `output/<src>/errors.log`. Coalesce duplicate errors.
- **Taxonomy-lookup investigation.** GBIF returned `no_match` for 42 of 43 Ashmead species. Either query format is wrong or GBIF genuinely doesn't cover Cynipidae well. Compare alternative sources (ITIS, Catalogue of Life, NCBI Taxonomy). Outcome: probably move to multi-source enrichment. Names stay as written regardless.
- **OCR integration test.** OCR path (`maybe_ocr` via `ocrmypdf`) is unit-tested but has never run end-to-end inside the pipeline — every paper has been above the chars/page threshold and skipped OCR. Triggerson 1914 or Loxaulus 2000 (~25-60 chars/page) would be a first real exercise.
- **Code-change auto-detection of cache invalidation.** Today the `STAGE_VERSION` constant is bumped manually per the new `CLAUDE.md` rule. Smarter options for the future: hash the stage's Python module file (conservative-correct but invalidates on whitespace edits), or some import-time signature. Decision: manual for now; revisit if bumps get missed in practice.
- **Block-triage cost on long papers.** ~$0.03–0.05 per typical paper at DeepSeek-V4-Flash prices. On a 1000-page compendium (Felt 1917, Gagne 2017) the per-block cost adds up. Future option: cheaper / smaller model once Llama-3.1-8B's Instructor-schema reliability issue is sorted, or a hybrid where the structural detector (`drop_repeated_blocks`) does a deterministic first pass and the LLM only sees survivors.

## Verification gaps

- **Cross-source recall measurement** is currently stale. Nicholls has been re-scored end-to-end with the post-block-triage + post-sibling-sharing code (95.0% recall, no regressions on the labels that were 100% before). Cuesta-Porta 2022 Druon (97.5% baseline), Gagne/Moser 2013 Hackberries (99.5% baseline), and the remaining 11 eval sources have NOT been re-scored against the current code. Need sequential re-runs to confirm no global regressions before the next architectural move.

## Failed / superseded approaches (do not redo)

- **Journal-specific regex header stripping** (`strip_page_headers` with patterns for Philippine Journal of Science, "AUTHOR: TITLE" all-caps headers). Deleted. Replaced first by the general frequency+pagination detector and now by the upstream LLM `block-triage` stage. Don't reintroduce per-journal regexes.
- **Per-tuple `(mention, generation)` agreement threshold in find-candidates.** Caused 27→13 candidate regression when the LLM's third sample disagreed on generation tag. Replaced with two-layer dedup: species-level threshold for survival, per-generation emission for every observed gen.
- **Llama-3.1-8B-Instruct for block-triage.** Cheap, but emits raw JSON arrays where Instructor expects wrapped objects; Pydantic parsing fails reliably. Swapped to DeepSeek-V4-Flash which uses the same Instructor + wrapped-object pattern as `find-candidates`. Same reason Llama-3.1-8B was rejected for find-candidates back on May 16: it doesn't follow nested schema instructions.
- **RootModel-of-list for Instructor response_model.** Tried as a workaround for Llama's raw-array output; Instructor's MD_JSON mode strips the surrounding `[ ]` and confuses Pydantic's JSON parser. Use a wrapped BaseModel with a `list` field instead — the pattern the rest of the pipeline already uses.
- **Parallel pipeline runs across multiple sources** for eval validation. Risks DeepInfra rate-limit and wastes API spend on partial failures. Sequential is the rule.
- **Numeric DB source_id as the `--source-id` flag.** The flag is a free-form run-name string (`nicholls`, `felt-1940`); the numeric ID lives only in `eval/pdf_source_map.py`. Conflating them creates wrong output paths.

## UI / Elixir side (tracked elsewhere)

Pipeline-side changes that need corresponding Elixir review-workspace work. Live on `alpha-ui`; UI agent has shipped the importer and workspace changes alongside the pipeline commit.

- Bundle importer accepts `schema_version: "1.4.0"` (which adds `generation` field, the structured `evidence_prose: list[ProseParagraph]` field, the `Evidence.quote` max_length bound, and various per-artifact bumps).
- Importer dedups species records by `(name, generation)`, persists `evidence_prose`.
- Workspace surfaces `evidence_prose` as the primary review panel; `description.value` demoted to derived secondary.
