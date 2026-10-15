# Gallformers import contract

How any tool, person or AI agent delivers what a Source (a paper, book, field guide or web page) says about galls into Gallformers. A producer turns one Source into a **package** of JSON files; Gallformers validates and imports it. This directory is the contract: the rules, the schemas, the vocabularies, examples, and the validator.

Status: format v3, draft. It has been tested on five Sources (old scans, a modern paper, a field guide, a web page) with a human-checked error rate of about 1% (`docs/import/producer-guide-background.md` has the decisions; mull matter `8546` has the trial). Gallformers' importer is not built yet.

## A package

One directory per Source:

| File | Phase | What it is |
|---|---|---|
| `document.json` | 1 Document | The Source converted to a [DoclingDocument](https://docling-project.github.io/docling/). Every quote in the batches points into it. |
| `taxonomy.json` | 2 Taxonomy batch | Taxonomic acts the Source states: new names, placements, synonymies, splits, common names. Empty when it states none. |
| `gall.json` | 3 Gall batch | Facts about Galls: Inducers, Hosts and other Relationships, Traits, range adjustments, common names, descriptions. |
| — | 4 Validate | `validate.py` checks the shape, the controlled values, and that every quote is in its document item. |
| `review.json` | 5 Review | A fresh reviewer checks every statement against the document and lists findings. |
| (`review.json`) | 6 Respond | The producer agrees (and fixes) or disagrees with each finding. Disagreements go to a human at intake. |

Every statement carries evidence: a verbatim quote and the document item it comes from. Names are written exactly as the Source writes them; Gallformers resolves them. Controlled values (Traits, places, relationship types) come from the vocabularies and carry the Source's own words in `as_written`.

## What's here

| Path | Read it when |
|---|---|
| `PRODUCER_GUIDE.md` | You produce batches (phases 1–3 and 6). **The rules.** Organised by phase. |
| `VERIFY_GUIDE.md` | You review batches (phase 5). |
| `GALLFORMERS_STATEMENTS.md` | Gallformers states its own Facts (observations, curator corrections). |
| `schema/` | JSON Schemas (2020-12) for `taxonomy.json`, `gall.json` and `review.json`; `common.schema.json` holds the shared parts. |
| `vocab/` | Controlled lists (`*.schema.json`), `places.json` (place names for codes), and `traits.json` (what each Trait value means, and how common Source terms map onto values). |
| `examples/` | Four complete packages with fictional Sources: `simple-paper`, `revision` (taxonomy), `retraction`, `gallformers-statement`. Start here to see the format. |
| `validate.py` | Phase 4, and the readiness check. |
| `tests/` | The validator's tests. |

## Producing a package with your own agent

Any agent can produce a package; the contract doesn't assume a particular tool. Give it:

1. **The document.** Convert the Source to a DoclingDocument (`document.json`) with [Docling](https://docling-project.github.io/docling/), and give the agent a readable rendering of its items (each with its reference, e.g. `#/texts/42`, and printed page). The reference producer does this for you (`produce convert`).
2. **The contract:** `PRODUCER_GUIDE.md`, the schemas, the vocab files (`places.json` is large: give the agent a way to look place names up rather than the whole file), and the examples.
3. **The task:** phase 2 (write `taxonomy.json`), then phase 3 (write `gall.json`), each validated with `validate.py` until clean.
4. **Review:** a separate, fresh agent with `VERIFY_GUIDE.md`, the guide, the vocab, the document and the two batches (not the producer's notes) writes `review.json`.
5. **Respond:** the producer answers each finding (`PRODUCER_GUIDE.md`, "Phase 6 — Respond").

The reference producer (`services/import-producer/`) does all of this with headless Claude Code; its prompts (`services/import-producer/prompts/`) show one way to instruct an agent.

## Validating

```
uv run priv/import/validate.py <package-dir>             # phase 4
uv run priv/import/validate.py --review <package-dir>    # ready to deliver?
python3 priv/import/validate.py <package-dir>            # without uv; needs jsonschema >= 4.18
```

A package is **ready** when `--review` passes. It prints any disputed findings (for the human at intake) as warnings.

Tests:

```
uv run --with pytest --with "jsonschema>=4.18" --with "referencing>=0.30" pytest priv/import/tests
```

## Where things are decided

- **Rules:** `PRODUCER_GUIDE.md` (this directory).
- **Why the rules are what they are, and what Gallformers does on import:** `docs/import/producer-guide-background.md`.
- **Open questions** (season, detachable, recorded range, aphid generations, historical plant names) are listed at the end of that document.
- Work tracking: mull matters `294c` (this contract), `e381` (the Gallformers side), `8546` (the trial).
