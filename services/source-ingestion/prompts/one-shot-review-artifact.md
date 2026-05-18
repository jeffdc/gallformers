# Experimental one-shot review-artifact prompt

This prompt asks a frontier model (Opus 4.x, GPT-class peers) to read a single
PDF or its extracted text and emit a complete `review_artifact.json` in one
shot — no multi-stage pipeline, no caching, no voting. It's a baseline for
comparing pipeline output quality and to test "what could the strongest
model do alone?"

**Use:** paste everything below the `---` line into the model as a single user
message, then attach the PDF (or paste the extracted text). For large papers,
also pass `--output-dir <path>` so the model can write files instead of
emitting JSON inline. The model returns either inline JSON or a one-line
confirmation pointing at written files.

Only schema-shape correctness is required. Field-level accuracy is welcome
but the bar is "the curator UI can render this without crashing."

---

You will receive a scientific paper about gall-inducing insects (Cynipidae,
Aphidoidea, Cecidomyiidae, etc.) plus, optionally, an `--output-dir` path.
Produce a `review_artifact.json` bundle matching the gallformers schema
(v1.5.0). The output is loaded by a strict Pydantic validator that forbids
extra fields and enforces every shape constraint.

**Schema correctness is the bar.** Field-level precision is welcome but not
required. Abstain liberally on anything the paper doesn't tell you.

## STEP 0 — Pre-flight (mandatory; do this before generating any JSON)

Skim the paper end-to-end. Then, in a short paragraph BEFORE any JSON output,
state:

1. **Subject count**: how many distinct species does the paper TREAT as a
   subject (see "Candidate selection" below — bibliographic citations and
   comparison-table rows don't count).
2. **Generation splits**: of those, how many will yield two records (paper
   describes both sexgen and agamic with *distinct* phenology/morphology
   per generation) vs one record (single generation, or both generations
   share a description).
3. **Projected record count**: `single_gen_subjects + 2 * dual_gen_subjects`.
4. **Output mode** (pick one based on projected count):
   - `≤ 5 records` → **inline**: emit the full JSON object as your response.
   - `6–40 records` and `--output-dir` was provided → **single file**:
     write to `<output_dir>/review_artifact.json` and respond with one line:
     `Wrote N records to <path>`.
   - `> 40 records` and `--output-dir` was provided → **batched**: write
     `<output_dir>/batch_001.json`, `batch_002.json`, … each a complete
     `review_artifact.json` with up to 20 records in `gall_records`, all
     sharing identical `source` and `document_metadata`. Then write
     `<output_dir>/manifest.json` with `{"batches": ["batch_001.json", …],
     "total_records": N, "schema_version": "1.5.0"}`. Respond with one line:
     `Wrote N records across K batches to <path>`.
   - If projected count is `> 5` and no `--output-dir` was provided →
     respond with `ERROR: paper has N subjects (~M records); rerun with
     --output-dir <path>`. Do not attempt inline output.

After the pre-flight paragraph, proceed to generate. **Do not skip the
pre-flight even for small papers** — it's the only check that prevents an
unbounded inline dump.

## Domain primer

- **Gall** = a plant deformation induced by an insect (or other organism).
  The gall is part of the plant, not the insect.
- **Gall-maker** = the insect that induces the gall. A separate organism from
  the gall itself.
- **Host** = the plant species the gall forms on (typically a *Quercus* for
  cynipid wasps).
- **Generation** — many cynipid wasps have alternating generations.
  `"sexgen"` (sexual) and `"agamic"` (asexual / parthenogenetic) are the
  named generations.
- **When to emit two records vs one** (overrides the old "always two" rule):
  - Paper gives *distinct descriptions per generation* (different host
    organ, different gall morphology, different phenology window) →
    **two records**, same `scientific_name`, different `generation`.
  - Paper says "alternating generations are known" but shares one
    phenology paragraph with no per-generation detail → **one record**
    with `generation: "unspecified"` and the shared text in evidence.
  - Paper describes only one generation → **one record** with that
    generation; do not emit a stub for the other.
- **`gall_traits` describes the GALL, not the insect.** Adult-insect
  morphology (antennae, wings, body color, mesosoma, mandibles, etc.) has
  no field in this schema — leave it out entirely.

## Cell shapes — the critical gotcha

Two shapes coexist; using the wrong one fails strict validation. Memorize
these four templates and copy-paste them as you build records.

**`EvidenceCell`** — used for `gall_maker.*` (non-name fields), `hosts[*]`
non-name fields, `location`, `gall_traits.detachable`, every cell in
`document_metadata`.

```json
{"value": "X", "evidence": [], "support_status": "supported", "confidence": 0.9}
```

Abstain:

```json
{"value": null, "evidence": [], "support_status": "abstained", "confidence": 0.0}
```

**`ScientificNameCell`** — extends EvidenceCell with `name_as_written` and
`taxonomy_lookups`. Used for `gall_maker.scientific_name`,
`gall_maker.taxonomy.*` (every populated rank), `hosts[*].scientific_name`.

```json
{"value": "Andricus", "name_as_written": "Andricus", "taxonomy_lookups": [], "evidence": [], "support_status": "supported", "confidence": 1.0}
```

Set `name_as_written` equal to `value` unless the paper writes the name
differently (abbreviated, with non-standard punctuation). Always emit
`taxonomy_lookups: []`.

**`TraitCell`** — used for `gall_traits.{color, shape, texture, walls,
cells, alignment, plant_part, form, season}`. NOT `value` — has `original`
and `suggested`.

```json
{"original": "bright red", "suggested": ["red"], "evidence": [], "support_status": "supported", "confidence": 0.9}
```

Abstain:

```json
{"original": null, "suggested": [], "evidence": [], "support_status": "abstained", "confidence": 0.0}
```

**`gall_traits.detachable`** is the lone EvidenceCell inside `gall_traits`.
Its `value` is from the closed enum `unknown | integral | detachable | both`.
When abstaining, use `"value": "unknown"` (NOT `null`).

## Closed enums

- `support_status`: `supported | contradicted | not_enough_evidence | needs_human_review | evidence_substring_mismatch | abstained`
- `confidence_bucket`: `high | medium | low`
- `generation`: `sexgen | agamic | unspecified`
- `Detachable`: `unknown | integral | detachable | both`
- `relevance` (on `ProseParagraph`): `high | medium | low`

## Controlled trait vocabulary

For `gall_traits.<trait>.suggested[]`, pick from these short lists when one
applies. If nothing fits, emit `"suggested": []` and keep `original`.

- `color`: red, yellow, green, brown, black, white, gray, pink, orange, purple
- `shape`: sphere, cylinder, cup, spindle, disc, kidney, irregular, conical
- `texture`: smooth, hairy, warty, ribbed, spiny, pubescent, glabrous
- `walls`: thick, thin, spongy, woody, fleshy, papery
- `cells`: monothalamous, polythalamous
- `alignment`: erect, drooping, integral, pendant
- `plant_part`: leaf, stem, bud, petiole, fruit, flower, root, twig, catkin, midrib
- `form`: oak apple, bullet, pip, plum, pocket, leaf curl, witches broom, blister, button, club
- `season`: Spring, Summer, Fall, Winter

## Candidate selection — what to emit

**Emit** a `GallRecord` for a species the paper TREATS as a subject:
provides morphology, host attribution, distribution, biology, or a dedicated
diagnosis/checklist entry. Annotated checklist entries (host plants +
lifecycle + distribution paragraph each) ARE subjects, even when minimal.

**Do NOT emit** for:

- Bibliographic citations ("Burks 1979").
- Comparison-table rows that just list a name + author + year with no body.
- "Differs from X" diagnostic asides where X isn't a subject of the paper.
- Synonymy-list entries ("= A. macrocarpae Bassett, 1890").
- Species mentioned only in passing in an intro or discussion paragraph
  (e.g., "X is widespread in Europe" with no dedicated treatment).

When in doubt: "Would removing every passage about this species
significantly reduce what the paper communicates about it?" If no — skip.

## Output shape

Each artifact is one JSON object. All fields below are required unless
marked nullable. Use the cell templates from the section above.

```json
{
  "schema_version": "1.5.0",
  "pipeline_name": "frontier-one-shot",
  "pipeline_version": "1.0.0",
  "generated_at": "<any ISO-8601>",

  "source": {
    "pdf_sha256": "<64 hex chars; '0'*64 is fine>",
    "pdf_filename": "<input filename>",
    "pdf_page_count": <int ≥ 1>,
    "source_text_sha256": "<64 hex chars>",
    "normalized_text": "<see below>"
  },

  "document_metadata": {
    "schema_version": "1.5.0",
    "title":    <EvidenceCell>,
    "authors":  [<EvidenceCell>, ...],
    "year":     <EvidenceCell>,
    "journal":  <EvidenceCell>,
    "volume":   <EvidenceCell or null>,
    "issue":    <EvidenceCell or null>,
    "pages":    <EvidenceCell or null>,
    "doi":      <EvidenceCell or null>,
    "language": <EvidenceCell>
  },

  "gall_records": [<GallRecord>, ...],
  "warnings": []
}
```

`normalized_text` cap: include the abstract, introduction, methods, and the
species-treatment text. If the full body exceeds ~30KB, include the
abstract + intro + concatenated treatment sections only; you can omit the
references list, acknowledgements, and back-matter tables. Evidence quotes
SHOULD be substrings of `normalized_text` when feasible, but this isn't
strictly enforced for this experiment.

### One `GallRecord`

```json
{
  "record_id": "R_001",
  "candidate_id": "C_001",
  "generation": "sexgen",
  "confidence_bucket": "high",
  "warnings": [],
  "gall_maker": {
    "scientific_name": <ScientificNameCell>,
    "authority":       <EvidenceCell>,
    "rank":            <EvidenceCell>,
    "taxonomy": {
      "kingdom":    null,
      "phylum":     null,
      "class_name": null,
      "order":      <ScientificNameCell or null>,
      "suborder":   null,
      "family":     <ScientificNameCell or null>,
      "subfamily":  null,
      "tribe":      <ScientificNameCell or null>,
      "genus":      <ScientificNameCell or null>,
      "subgenus":   null
    },
    "aliases":      [],
    "common_names": []
  },
  "hosts": [
    {"scientific_name": <ScientificNameCell>, "authority": null, "rank": null}
  ],
  "gall_traits": {
    "color":      <TraitCell>,
    "shape":      <TraitCell>,
    "texture":    <TraitCell>,
    "walls":      <TraitCell>,
    "cells":      <TraitCell>,
    "alignment":  <TraitCell>,
    "plant_part": <TraitCell>,
    "form":       <TraitCell>,
    "season":     <TraitCell>,
    "detachable": <EvidenceCell, value from Detachable enum>
  },
  "location": <EvidenceCell>,
  "evidence_prose": [
    {
      "span_id": "S_0001",
      "page": 1,
      "char_start": 0,
      "char_end": 120,
      "text": "<paragraph text>",
      "is_mention": true,
      "is_cited": true,
      "cited_by_fields": ["gall_maker.scientific_name", "hosts[0].scientific_name"],
      "name_occurrences": 1,
      "relevance": "high"
    }
  ]
}
```

### `candidate_id` vs `record_id`

- `record_id` is unique per row: `R_001`, `R_002`, … one per record.
- `candidate_id` is unique per biological species: both generations of one
  species share a `candidate_id` (`C_001`). Different species get different
  `C_xxx`.

## Placeholder rules

| Field                                | Acceptable placeholder                                        |
|--------------------------------------|---------------------------------------------------------------|
| `schema_version`                     | `"1.5.0"` (literal)                                           |
| `pipeline_name` / `pipeline_version` | `"frontier-one-shot"` / `"1.0.0"`                             |
| `generated_at`                       | any ISO-8601 datetime                                         |
| `pdf_sha256` / `source_text_sha256`  | `"0"` × 64                                                    |
| `pdf_page_count`                     | best estimate (integer ≥ 1)                                   |
| `Evidence.char_start` / `char_end`   | any pair with `char_end > char_start ≥ 0` (`0`/`1` is fine)   |
| `Evidence.block_id`                  | `"S_0001"`, `"S_0002"`, … incrementing across the artifact    |
| `Evidence.quote`                     | substring of source text, ≤ 2000 chars                        |

## Worked example — single-species paper (inline mode)

Pre-flight paragraph:

> Subjects: 1. Generation splits: 0 dual, 1 single. Projected records: 1.
> Mode: inline.

Then the JSON (abbreviated here — full example uses every required field):

```json
{
  "schema_version": "1.5.0",
  "pipeline_name": "frontier-one-shot",
  "pipeline_version": "1.0.0",
  "generated_at": "2026-05-18T12:00:00Z",
  "source": { "pdf_sha256": "0000000000000000000000000000000000000000000000000000000000000000", "pdf_filename": "input.pdf", "pdf_page_count": 12, "source_text_sha256": "0000000000000000000000000000000000000000000000000000000000000000", "normalized_text": "..." },
  "document_metadata": { "schema_version": "1.5.0", "title": {"value": "...", "evidence": [], "support_status": "supported", "confidence": 0.9}, "authors": [...], "year": {...}, "journal": {...}, "volume": null, "issue": null, "pages": null, "doi": null, "language": {"value": "en", "evidence": [], "support_status": "supported", "confidence": 1.0} },
  "gall_records": [ /* one record per the GallRecord template */ ],
  "warnings": []
}
```

## Worked example — faunistic checklist (batched mode)

Pre-flight paragraph:

> Subjects: 79 Cynipini species. Generation splits: 51 dual, 28 single.
> Projected records: 130. Mode: batched (output-dir provided). Will write
> 7 batches of up to 20 records each plus manifest.json.

Then write `batch_001.json` … `batch_007.json` and `manifest.json`. Each
batch has identical `source` and `document_metadata`; `gall_records` is the
slice for that batch. Respond with one line:
`Wrote 130 records across 7 batches to /tmp/out/.`

Within each record, abstain liberally:

```json
"gall_traits": {
  "color":      {"original": null, "suggested": [], "evidence": [], "support_status": "abstained", "confidence": 0.0},
  "shape":      {"original": null, "suggested": [], "evidence": [], "support_status": "abstained", "confidence": 0.0},
  "texture":    {"original": null, "suggested": [], "evidence": [], "support_status": "abstained", "confidence": 0.0},
  "walls":      {"original": null, "suggested": [], "evidence": [], "support_status": "abstained", "confidence": 0.0},
  "cells":      {"original": null, "suggested": [], "evidence": [], "support_status": "abstained", "confidence": 0.0},
  "alignment":  {"original": null, "suggested": [], "evidence": [], "support_status": "abstained", "confidence": 0.0},
  "plant_part": {"original": "bud galls", "suggested": ["bud"], "evidence": [], "support_status": "supported", "confidence": 0.9},
  "form":       {"original": null, "suggested": [], "evidence": [], "support_status": "abstained", "confidence": 0.0},
  "season":     {"original": "appear in August, mature in autumn", "suggested": ["Summer", "Fall"], "evidence": [], "support_status": "supported", "confidence": 0.85},
  "detachable": {"value": "unknown", "evidence": [], "support_status": "abstained", "confidence": 0.0}
}
```

A checklist entry will typically supply `plant_part`, `season`, host
species, location, and the taxonomic backbone (order/family/tribe/genus).
Everything else: abstain. Don't synthesize trait values from genus-level
knowledge — the paper-level evidence is what the validator scores against.

## Output discipline

- **Inline mode**: output the pre-flight paragraph, then ONLY the JSON
  object. No Markdown fences around the JSON, no postscript.
- **File mode**: output the pre-flight paragraph, then write the files,
  then ONE line confirming what was written. Do not paste file contents.
- All required fields must be present. Use `null` (not omitted) for nullable
  fields when you have nothing to say.
- When a field is unknown, abstain following the EvidenceCell or TraitCell
  template — do not invent values.
- Genus and family for gall-wasp papers can usually be derived from the
  scientific name + the paper's stated tribe (e.g., "Cynipidae: Cynipini"
  in the title). Higher ranks (kingdom, phylum, class) — leave as `null`
  unless the paper explicitly names them.
- If you hit a structural ambiguity mid-generation, emit the record with
  the affected cell abstained and add a string to the record's `warnings[]`
  describing what was unclear. Don't guess.
