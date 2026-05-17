# Phase 2 — Improve per-species account assembly: design

## Baseline state (established 2026-05-16)

Two real pipeline runs scored against the eval-set labels using the `phase-b-extract-facts.yaml` config:

| Source | Species | Matched | Avg eval ceiling | Avg pipe cov | Recall vs ceiling |
|---|---:|---:|---:|---:|---:|
| Nicholls 2022 | 27 | 26/27 | 98.9% | 87.4% | **88.4%** |
| Cuesta-Porta 2022 Druon | 22 | 21/22 | 87.5% | 85.4% | **97.5%** |

**Headline**: the current pipeline's `evidence-pack` stage is *very strong* on modern Zootaxa — Cuesta scored 97.5% recall vs the matcher's recoverability ceiling. Where the matcher couldn't recover text from the PDF, the pipeline correctly captured what was recoverable and nothing more.

The Nicholls 88% gap is **almost entirely** explained by one structural mismatch:

- The eval-set DB partitions Cynipid species into separate `(sexgen)` and `(agamic)` rows because the two generations are biologically distinct and the literature treats them as separate entities.
- The current `find-candidates` produces one candidate per species ("Andricus balanaspis"), so both generation rows share a single evidence pack.
- When most of the paper text is about the sexual generation, the sexgen labeled entry scores ~95% and the agamic entry scores ~34%. The aggregate drags the source average down.

Cuesta avoids this confound because most of its species are described agamic-only in this paper — no generation split → no penalty.

## What this implies for Phase 2 scope

Originally this doc framed Phase 2 as a wholesale architectural rewrite — replace `evidence-pack` with an LLM-driven span-classification stage. The baseline numbers say that's overkill for modern Zootaxa.

**Revised scope, in priority order**:

1. **Generation-aware candidate splitting** (likely closes most of the Nicholls gap; cheap to implement; no LLM-architecture change required). Validate against re-running the eval scorer.
2. **Measure on format-diverse sources** (compendia like Felt 1917 once OCR is available, plus a Weld and an Ashmead). Only commit to the LLM-assembly architectural change if these reveal large gaps that generation splitting + the current `evidence-pack` can't close.
3. **LLM-driven `assemble-account` stage** — implement only if (2) shows it's needed. Scoped as a precision tool for harder formats (keys, compendia, papers with interleaved species accounts), not as a universal replacement.

The Phase 2 deliverable for the curator (per-species verbatim prose as the primary review surface) stays the same. The implementation path to it is narrower than originally proposed.

## Why per-species verbatim prose is the goal

This part is unchanged from the original design:

The pipeline's job is to make per-species verbatim prose the primary deliverable to the human curator, with structured trait extraction demoted to a tagging layer on top. The current pipeline's `extract-facts` stage collapses each candidate into structured trait cells plus a single free-text `description` cell — which is too narrow even though `evidence-pack` itself is broad. The fix is to surface the evidence-pack prose (or its successor) as the curator's primary review surface, not buried inside intermediate stage state.

## Step 1 — Generation-aware candidate splitting

Cynipid gall wasps have alternating sexual and asexual (agamic) generations that are biologically distinct: different morphology, different gall, different host part, different season. The literature treats them as separate entities, and the gallformers DB models them as separate species rows (`(sexgen)` and `(agamic)` suffixes).

This pattern recurs beyond Cynipidae:
- Aphidoidea: alate vs apterous morphs, sexual vs parthenogenic forms.
- Some Cecidomyiidae: winter vs summer generations on the same host.
- Phylloxera: similar lifecycle alternation.

The generalization: any time a paper describes **a single species' two distinct biological forms separately**, the pipeline should treat them as separate candidates.

**Concrete changes**:

- `find-candidates` adds a `generation` field to each candidate. Valid values: `"sexgen"`, `"agamic"`, `"both"` (described together), `"unspecified"` (paper doesn't make the distinction or the species lacks generation alternation).
- When a paper describes both generations of the same species in separately identifiable passages, `find-candidates` emits **two candidates** — `{gall_maker_mention: "Andricus balanaspis", generation: "sexgen"}` and `{gall_maker_mention: "Andricus balanaspis", generation: "agamic"}`.
- `evidence-pack` uses the generation as a filter when selecting spans for each candidate. The paragraph that introduces the species heading typically belongs to one of them or to both.
- The eval scorer already partitions labels by generation suffix, so this change should improve recall numbers immediately on Nicholls.

**Prompt detection cues for generation** (the model should look for, but is not limited to):
- Explicit labels: "sexual generation", "asexual generation", "agamic generation", "spring brood", "summer brood".
- Implicit cues: "Sexual female (Figs ...)", "Males ...", "The asexual generation has been found on ...".
- Cross-reference cues: "Asexual generation, see Bassett (1864) and Weld (1922a)" indicates the paper *references* but does not *describe* the asexual generation — in that case, only emit the sexgen candidate.

**Expected impact**: the Nicholls baseline rises from 88% toward Cuesta's 97%, because the agamic entries (currently ~34% pipe coverage) get their own evidence packs.

**Open question**: how does `evidence-pack` actually partition spans by generation when the source paragraphs interleave? Options:
- LLM tags each mention span with its generation context during `find-candidates`; `evidence-pack` filters on that.
- `evidence-pack` runs a per-span generation classifier itself.
- The two candidates share spans where generation isn't determinable; the filter only excludes spans clearly tagged as the other generation.

The cheapest is to add generation tagging to `find-candidates` and have `evidence-pack` honor it. Start there.

## Step 2 — Measure on format-diverse sources

After Step 1 lands, re-run the eval scorer to confirm the Nicholls gap closed. Then run the pipeline on additional eval-set sources that exercise different document formats:

- **Compendium / key**: Felt 1917 *Key to American Insect Galls*, Felt 1940 *Plant Galls and Gall Makers* — both currently blocked on OCR (see separate OCR follow-up).
- **Mid-century narrative**: Weld 1922, Weld 1926, Kinsey 1929 — likely need OCR cleanup too.
- **Cecidomyiidae**: Gagne 2008 *Gall Midges of Hickories*, Gagne/Moser 2013 *Hackberries* — different family terminology; born-digital, no OCR needed.
- **Field guide**: Nastasi & Davis 2022 — born-digital, no OCR needed.

For each, compute pipeline `recall vs ceiling`. If the current pipeline keeps clearing >=90% across format diversity, **the LLM-assembly stage is not needed**. If specific formats drop into the 60-80% range despite generation splitting, that's evidence for Step 3.

## Step 3 — LLM-driven `assemble-account` stage (only if Step 2 motivates it)

The original design proposed replacing `evidence-pack` with a per-candidate LLM span-classification call. The rationale: handle papers where relevant prose is scattered across paragraphs that don't name the species (pronoun references, continuation prose, comparative diagnoses), which the current mention-span-id + context-window approach can miss.

Implementation only if Step 2 shows specific format types where the current pipeline systematically underperforms. The stage shape (if needed):

- **Input**: candidate (with generation tag) + full normalized text with span IDs.
- **Output**: `species_account.prose` (ordered verbatim paragraphs with span-id provenance) and `species_account.span_ids` (ordered list).
- **How**: LLM call per candidate, framed as span-level relevance classification. `n_samples: 3` + agreement vote. No section-structure assumptions.
- **Cross-model verifier** (`verify-account`): different-family LLM prunes the assembled set. The "different family" principle already in use (DeepSeek vs Qwen) reduces correlated errors.

This stage **adds cost** (one LLM call per candidate, possibly two with verifier) and is justified only if the cheaper alternative (Step 1 + current `evidence-pack`) underperforms on real sources.

## `extract-facts` becomes a trait tagger

Whether or not Step 3 happens, `extract-facts` evolves:

- The prompt's framing shifts from "find everything about this species" to "tag traits in this candidate-specific prose block; the prose is already curated to be relevant; your job is just to identify trait values."
- The `description` field is removed from `_LLMFacts` — the full prose is now `evidence_pack.txt` (Step 1) or `species_account.prose` (Step 3), both surfaced to the curator directly.
- `location` is similarly removed; distribution prose belongs in the account.
- Trait fields stay. Per-field evidence citations and substring gate unchanged.

## Output artifact changes

`review_artifact.json` gets a `species_accounts` field per candidate:

```json
{
  "candidate_id": "C_004",
  "gall_maker": "Andricus balanaspis",
  "generation": "sexgen",
  "prose": "Andricus balanaspis (Weld, 1922), comb. nov., sexual generation\n\nSynonyms: Callirhytis balanaspis Weld, 1922b: 22...\n\nDiagnosis. The sexual generation of A. balanaspis most closely resembles three species from Florida...\n\n...",
  "span_ids": ["S_0234", "S_0235", "S_0237", "S_0253", "S_0254", "S_0255", "S_0256"]
}
```

Existing structured-fact output (trait cells, hosts, aliases) stays, minus `description` and `location` cells.

## Pipeline shape after Step 1

```
extract → preprocess → sectionize → metadata
   → find-candidates (now emits per-generation candidates with `generation` field)
   → evidence-pack (now filters by generation when relevant)
   → extract-facts (now trait-tagger over the evidence pack)
   → verify (substring gate, unchanged)
   → verify-claims (unchanged)
   → taxonomy-lookup (unchanged)
   → assemble-review (updated artifact shape with `species_accounts`)
   → bundle (unchanged)
```

If Step 3 ships, `evidence-pack` is replaced by `assemble-account` + `verify-account` in the same slot.

## Risks / failure modes to watch for

- **Generation tagging false negatives**: `find-candidates` misses the generation cue and emits one candidate when two are described. Mitigation: prompt iteration against the eval set; the eval scorer will surface this as low recall on the missed generation's labels.
- **Generation mis-assignment in `evidence-pack` filter**: a span is attributed to the wrong generation. Mitigation: when uncertain, the filter should keep the span for both candidates rather than dropping it.
- **Adjacent-species drift** (Step 3 only): assembler includes a paragraph about species B in species A's account. Mitigation: cross-model verifier.
- **OCR-damaged papers**: orthogonal issue; tracked separately. Won't affect Step 1 measurements on born-digital papers.

## Success criteria

Anchored to the eval set:

- **Step 1 success**: Nicholls recall vs ceiling rises from 88% to **>=95%** with no regression on Cuesta (currently 97.5%).
- **Step 2 success**: at least 6 eval-set sources scored, spanning modern Zootaxa + Cecidomyiidae + field guide + at least one compendium (post-OCR). Median recall vs ceiling >=90%, no source below 70%.
- **Step 3 success** (if undertaken): on the sources that motivated it, recall vs ceiling rises to >=90% without dropping any Step-1-passing source below its baseline.
- **No regression**: every (species, source) pair that hit >=95% on the Step 1 baseline still hits >=90% after each subsequent change.

## Implementation order

1. **Step 1**: extend `find-candidates` schema + prompt for generation tagging; teach `evidence-pack` to filter by generation. Re-run on Nicholls + Cuesta. Score.
2. Run pipeline on 4-6 more born-digital eval-set sources. Score.
3. Decide whether Step 3 is needed based on (2). If yes, build `assemble-account` + `verify-account` and rerun.
4. Rewrite `extract-facts` as trait-tagger (independent of whether Step 3 happens). Schema migration: drop `description` and `location` cells from `_LLMFacts`.
5. Update `review_artifact.json` schema and downstream Elixir consumer to surface `species_accounts`.

Each step gates on the eval scorer. Reverts are cheap.

## What this design does NOT decide

- The exact prompt wording for generation tagging — needs iteration.
- The Elixir review-UI changes — separate work, scoped after the pipeline output stabilizes.
- The OCR-vs-pymupdf decision for older PDFs — tracked separately.
- Cost-optimization moves — premature until we measure real cost.

## What changed from the original design

The original draft of this doc proposed a wholesale replacement of `evidence-pack` with an LLM-driven `assemble-account` stage. The Cuesta baseline (97.5%) showed the current pipeline is already strong on modern narrative papers when generation splitting isn't a confound. Generation splitting alone may close most of the Nicholls gap. The LLM-assembly architecture is now scoped as a contingent precision tool for harder formats, only implemented if Step 2 measurements motivate it.
