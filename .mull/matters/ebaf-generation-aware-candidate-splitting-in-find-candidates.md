---
status: raw
tags: [design]
created: 2026-05-17
updated: 2026-05-17
epic: source-ingestion
---

# Generation-aware candidate splitting in find-candidates

# Generation-aware candidate splitting in find-candidates

## Goal

Move Nicholls 2022 recall vs ceiling from 88% → ≥95% by emitting separate candidates for each described biological generation. No regression on Cuesta 2022 Druon (97.5%) or Gagne/Moser 2013 Hackberries (99.5%).

The change generalizes beyond Cynipidae: aphid alate/apterous morphs, some Cecidomyiidae winter/summer generations, Phylloxera. Any case where one species' two biological forms are described separately in a paper.

## Scope

**In this bundle:**
- Schema: add `generation` field to candidates and gall records.
- `find-candidates` prompt rewrite for generation detection and per-generation candidate emission.
- `find-candidates` dedup keyed on `(mention, generation)`.
- `extract-facts` plumb-through (candidate.generation → GallRecord.generation; one-line prompt addition).
- Eval scorer match on `(name, generation)` instead of stripping the suffix.
- Validation runs on Nicholls / Cuesta / Gagne 2013.

**Deferred (separate matters):**
- `extract-facts` trait-tagger refactor (drops `description`/`location` cells). Has its own regression surface; bundling would mask the Step 1 recall signal.
- LLM-driven `assemble-account` stage. Gated on measurement after this lands.
- Elixir review-workspace UI consumer changes. Tracked in the UI impact log below; the Elixir-side work belongs in matter 8905 or a follow-on.

## Approach

**Path A — span partitioning at find-candidates time.** The LLM emits two candidates with the same `gall_maker_mention` but different `generation` and different `mention_span_ids`. Evidence-pack stays mention-span-driven and unchanged — it just gets two candidates for dual-generation species and builds two packs as if they were unrelated species.

Why not Path B (per-span generation tags + evidence-pack-side filtering): complicates schema, complicates dedup across self-consistency samples, no clear upside. The LLM is already selecting relevant spans per candidate — we extend that, not add a parallel mechanism.

## Schema changes

`_LLMCandidate` (`find_candidates.py`):
- Add `generation: Literal["sexgen", "agamic", "unspecified"]` — required.

`Candidate` (`schemas.py`):
- Add same field, same enum.

`GallRecord` (`schemas.py`):
- Add `generation: Literal["sexgen", "agamic", "unspecified"]` — required.

Three-value enum, not four. The doc-original "both" value collapses into "unspecified" — downstream behavior is identical for either value, and adding "both" later is reversible if a measurement motivates it.

Bundle `SCHEMA_VERSION` bumps `1.0.0` → `1.1.0`. Backwards-compatible addition (no field removal); importer can default missing `generation` to `"unspecified"` on old bundles if needed.

## find-candidates prompt changes

Edits to `prompts/find-candidates.md`:

1. **New section: "Generation tagging"** — explains sexgen/agamic/unspecified, with cue examples (sexual generation, asexual generation, agamic generation, spring brood, summer brood, "Sexual female (Figs ...)", "Males ...", "The asexual generation has been found on ..."). Includes the cross-reference cue: `"Asexual generation, see Bassett (1864)"` indicates the paper references but does not describe the asexual generation — emit only the sexgen candidate.

2. **Replace "one candidate per distinct species"** (current §"How many candidates to emit", line 69) with **"one candidate per distinct (species, generation) pair when the paper describes both generations in separately identifiable passages; one candidate with `generation: unspecified` otherwise"**.

3. **Keep the stripping rule** (current line 59 "sexual generation Andricus quercuscalicis" → "Andricus quercuscalicis"). The mention stays clean; generation is the separate structured field.

4. **Add a worked example** for a dual-generation case (Cynipid sexgen + agamic emitted as two candidates with overlapping mention_span_ids only where the prose genuinely covers both).

5. **For each candidate, `mention_span_ids` should now contain spans relevant to *that generation*.** Spans that genuinely cover both (intro paragraphs, taxonomy treatments at the species-level) may appear in both candidates' span lists.

## Dedup logic

`find_candidates.py`:
- `_normalize_mention` stays as-is for the mention name.
- The grouping key in the dedup loop becomes `(_normalize_mention(c.gall_maker_mention), c.generation)`.
- Sample agreement counted per `(mention, generation)` bucket.
- Cross-sample disagreement on whether to split (e.g., 1 of 3 says "unspecified", 2 of 3 emit sexgen+agamic): resolved by the existing agreement-threshold mechanism. With `threshold=2` and the 2-of-3 split case, both split candidates survive and the "unspecified" candidate is dropped.

## extract-facts changes

`extract_facts.py`:
- Pass `candidate.generation` through to the resulting `GallRecord.generation`.
- Add a one-line system-prompt addition: `"This evidence pack is for the {generation} generation of {gall_maker}. Restrict trait extraction to facts about that generation."` (Skip when `generation == "unspecified"`.)

No logic change to evidence-pack-driven extraction. No removal of `description`/`location` cells in this bundle — that's the deferred trait-tagger refactor.

## Eval scorer changes

`eval/score_run.py`:
- Stop stripping the ` (sexgen)` / ` (agamic)` suffix from DB labels.
- Parse the suffix into a `(base_name, generation)` tuple. Labels without a suffix get `generation: "unspecified"`.
- Match a labeled species to a pipeline candidate when `(base_name, generation)` matches `(candidate.gall_maker_mention, candidate.generation)`.
- An `"unspecified"` pipeline candidate is allowed to match a sexgen *or* agamic label only when no generation-matching candidate exists — i.e., the pipeline failed to split. This is graceful degradation for the pre-change baseline; once Step 1 is live we should rarely fall back to it.

## Validation

After implementation:
1. Re-run pipeline against three sources: Nicholls 2022, Cuesta-Porta 2022 Druon, Gagne/Moser 2013 Hackberries.
2. Score with updated `score_run.py`.
3. Targets:
   - Nicholls 2022: recall vs ceiling ≥95% (baseline 88.4%).
   - Cuesta-Porta 2022 Druon: within 1 point of 97.5% baseline.
   - Gagne/Moser 2013 Hackberries: within 1 point of 99.5% baseline.
4. If Nicholls misses target: triage by sampling a missed-generation candidate.
   - Prompt failure: LLM didn't detect the generation cue → iterate on prompt.
   - Schema failure: Instructor rejected the output → schema or repair-retry tuning.
   - Scorer failure: matching logic dropped a valid match → scorer fix.

## UI impact log

Changes in this bundle that the Elixir review workspace (matter 8905, branch `alpha-ui`) will need to consume:

- **New `generation` field on `GallRecord`** in `review_artifact.json`. Values: `"sexgen"`, `"agamic"`, `"unspecified"`. Importer should ingest this field. Likely maps to the gallformers `Species` name-suffix convention (`"Andricus balanaspis (sexgen)"`) at import time; the gallformers side is upstream of public taxonomy and uses suffixes to model separate species rows per generation.

- **Multiple `GallRecord`s per source species are now possible.** For Cynipid and aphid papers, expect the importer to receive two records sharing the same `gall_maker.scientific_name.value` but different `generation` values. The current importer's dedup behavior on duplicate gall_maker within one bundle needs verification — if it dedupes by name, dedup logic must change to dedup by `(name, generation)`.

- **Bundle `SCHEMA_VERSION` bump** `1.0.0` → `1.1.0`. Confirm whether the Elixir importer is strict about `schema_version` matching. If so, importer needs to accept `1.1.0` (additive change; treat missing `generation` on old bundles as `"unspecified"`).

## What this design does NOT decide

- Exact prompt wording for generation detection — needs iteration against the eval set.
- Whether the bundle importer should auto-suffix the species name (`(sexgen)` / `(agamic)`) at import time or carry generation as a separate column on `source_ingestion_species`. Owned by the Elixir-side change.
- Trait-tagger refactor of `extract-facts` — separate matter, gated on Step 1 landing cleanly.

