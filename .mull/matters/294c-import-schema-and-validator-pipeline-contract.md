---
status: raw
created: 2026-10-06
updated: 2026-10-06
epic: taxonomy
relates: [8567, e381]
blocks: [b119, 8546]
---

# Import schema and validator (pipeline contract)

# Import schema and validator (pipeline contract)

Step 1 of the reordered plan (`8567`, 2026-10-06). Turns the `e381` format into a committed, enforceable contract, because **the schema is the write interface**: any tool, screen, human, or LLM that produces valid JSON — a whole batch or a fragment of one — can deliver updates to the data. Together with the curator delta view, it is the new admin UI. Format details live in `e381`; this matter holds the work.

## Decided (Jeff, 2026-10-06)

- **The pipeline is an LLM with skills/docs plus this validator.** The Python POC in the repo does not carry forward. Adam produces batches with frontier models and says there is budget for it.
- **Every write is a batch** (`8567` rule 12, restated): no hard dependency on the LLM — a small form that emits a fragment is as valid a producer as the pipeline.
- **Quotes are critical.** The locator is a **quote** (required for literature) plus a page hint. Character offsets are dropped: an LLM can't produce them reliably and nothing would catch them being wrong, whereas a quote is checkable.
- **The LLM produces a plain-text rendition** of the Source when it can. Gallformers stores it privately, and shows it publicly only if the license allows. Gallformers verifies each quote against it (fuzzy match).
- **Denials are explicit, never inferred from omission:** a Source that lists hosts does not deny the ones it leaves out. This is an instruction to the producer.
- **`name_as_written` is kept on attributions** (not just on batch references), so Facts can be re-resolved after a taxonomic split.
- **Two-layer validator:**
  1. **The JSON Schema file** — shape and controlled values; runs in any standard validator, so the LLM's tools or Adam's setup need no Gallformers code.
  2. **A Gallformers dry-run import** (mix task first; the upload screen wraps it later) — what a schema can't check: references resolve, qualifiers point at Relationships, IDs exist, quotes found in the text.
- **The LLM's skills/docs derive from the domain doc and `e381`,** so the domain doc becomes the pipeline's instructions, not just our reference.

- **Taxon references resolve against today's taxonomy, taken as accurate** (2026-10-06): no taxonomy changes during imports; old names resolve through synonymy (aliases). Taxonomic Facts in batches stay phase 2.

## Draft (2026-10-07, branch `taxogall`, uncommitted)

`priv/import/` holds the v3 draft, written from `e381` v3 decisions 1–12:
- `schema/common.schema.json`, `schema/taxonomy.schema.json`, `schema/gall.schema.json` — JSON Schema 2020-12, strict (`unevaluatedProperties: false`), dispatching on `kind` / `trait` / `type` / `qualifier` with `if`/`then` rather than `oneOf`, so errors name the exact field and list allowed values (an LLM can self-correct from them).
- `vocab/` — traits, relationships (types grouped by endpoint kinds, qualifiers), ranks, licenses, place codes (4,547) plus `places.json` (code, name, type) for mapping. Extracted from the database 2026-10-07; a mix-task generator should replace the hand extraction. `form` excludes "non-gall".
- `PRODUCER_GUIDE.md` — rules first, rationale second, for an LLM and a developer; includes the layer-2 (dry-run) checklist.
- `examples/` — simple paper, revision (taxonomy + gall), Gallformers statement, retraction. Fictional Sources and quotes; no `document.json`.

- `validate.py` — the layer-1 validator for producers (standalone; `uv run` reads its dependencies from the file header). Accepts batch files or package directories; each error names the exact field and lists allowed values.

**Checked:** all examples validate; 31 mutations (unknown values, wrong endpoint kinds, missing `as_written`, extra properties, ranks above family, `whole_item` misuse, bad `unmapped` entries, …) are all rejected. The mutation test lives in the session scratchpad, not the repo — worth committing as the validator's test suite.

**Not yet:** the layer-2 dry run (Elixir); the vocab generator; a real DoclingDocument in an example; producer-side quote checking (finding each quote in its Docling item needs no Gallformers data, so `validate.py` could do it — not built, a candidate).

## Admin UI as a JSON editor (idea, Jeff, 2026-10-07)

If every write is a batch, the admin UI becomes **a tool for manipulating batch documents** — what it offers can evolve over time, and basic support should be cheap: forms generated from the schema (which argues for rich `description`s and complete enums), validator feedback inline, `add`-mode Gallformers batches for corrections. Approved batches stay immutable; a correction is a new batch.

## Problem to solve: Source descriptions

Today each Gall page shows a passage per Source (`species_source.description`: 8,074 of them, ~610 characters on average; 1,082 marked default) — **excerpts (quotes) from the Source documents**. The pipeline produces short quotes as evidence per Fact, which doesn't replace them. **Decided (Jeff, 2026-10-07): direct quotes only** — a `description` Fact is a collage of verified quotes; no producer summaries (`e381` v3 decision 10). Still open: how licensing limits public display of verbatim passages from All Rights Reserved Sources (today's site already shows such excerpts).

Related: `species_source.externallink` (2,999) holds **deep links to the page in a scanned Source** (BHL, HathiTrust, archive.org) — page locators. The pipeline reproduces them (they fit the page hint) or they migrate. A few Sources are websites with a page per species (e.g. *Aphids on the world's plants*), so "the Source" is many pages.

## To work through

- Close `e381`'s open items: evidence/locators (now quote-based), the generation vocabulary, validation beyond the schema.
- What a **fragment** is: a partial batch? a single Gallformers statement?
- Quotes when no plain text can be produced (e.g. a scan the LLM can't read).
- Where the schema lives, how its controlled-value lists are generated from Gallformers' vocabulary, and how it is versioned.
- How the validator reaches Adam's setup.
- The LLM skill/doc set: what exists, who writes it, how it is tested.

