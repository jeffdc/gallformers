---
status: raw
created: 2026-10-03
updated: 2026-10-06
epic: taxonomy
relates: [1121, 8567, 294c]
---

# Import interface: pipeline to Gallformers

The contract by which any producer delivers data into Gallformers. It is designed fresh from the domain model ([`docs/domain/domain-model.md`](../../docs/domain/domain-model.md)) and the Sources–Facts design in matter `8567`. **It is the write interface** (2026-10-06): any tool, screen, human, or LLM that produces valid JSON — a batch or a fragment of one — can deliver updates. The pipeline is an **LLM with skills/docs plus the validator**; the Python POC in the repo (and the matters built around it: `7fda`, `7c67`, `fa48`, `9314`, `4fef`, `7a83`, `db6f`) does not carry forward and needs reconciling. Making this format a committed schema and validator is matter `294c`.

## Decisions

- **Delivery:** the pipeline writes a batch to the private S3 bucket; an Oban job imports it as unpublished. A curator upload on an admin page is a UI wrapper around the same path.
- **Unit:** one Source per batch. The Source is the replacement key.
- **Stances, not separate withdrawals:** every Fact in a batch carries a **stance** — *confirm* or *deny*. A denial is a Fact with stance *deny*, identified by its natural key; it needn't match anything already published. What it does is decided by the recency rule (`8567`).
- **Authorship date:** every Source carries the date it was authored, as precise as known (year at minimum). The recency rule depends on it.
- **Retractions:** a batch whose Source is a retraction notice can declare that it **retracts** another Source. Retractions must also be recordable by a curator in the admin UI.
- **The producer is responsible for clean data.** Every controlled value must be exact and is enforced by the schema: trait values, generation terms, relationship types, qualifier values, alias types, license, Source kind, place codes. A batch with an unknown value is rejected, never fixed up in the admin tool. **The only Gallformers-side work is ID lookup** for entities (Galls, taxa, Sources).
- **Entity references:** every Gall and taxon reference carries `name_as_written`; IDs (Gallformers Gall ID, Gallformers taxon ID, Gallformers Source ID) are optional. The pipeline may start with none and grow stronger; Gallformers resolves every reference itself, against its own taxonomy and Galls, and validates any ID it is given. A batch can propose a new Gall entry through a batch-local reference.
- **Qualifiers are their own Facts,** pointing at the Relationship Fact they qualify through its batch-local ID.
- **Taxonomic Facts (phase 2):** once the taxonomy system exists, a batch can also carry taxonomic Facts (name, authorship, rank, placement, synonymy) and propose new taxa. Batch-local references then span both systems, and taxonomic Facts are applied before gall Facts.
- **License** uses exactly the `Gallformers.Licenses` list: Public Domain / CC0, CC-BY, CC-BY-SA, CC-BY-NC, CC-BY-NC-SA, CC-BY-ND, CC-BY-NC-ND, All Rights Reserved.
- **Plain-text rendition:** the LLM produces a plain-text version of the Source when it can. Gallformers stores it privately; it is shown publicly only if the license allows.
- **Quotes are the evidence (2026-10-06).** Each Fact from literature carries a **quote** plus a page hint; Gallformers verifies the quote against the plain text (fuzzy match). Character-offset locators are dropped: an LLM can't produce them reliably and nothing would catch them being wrong. Quotes also make sample audits cheap.
- **Denials are explicit, never inferred from omission (2026-10-06).** A Source that lists hosts does not deny the ones it leaves out; a `deny` stance needs the Source to say so.
- **`name_as_written` is stored on the attribution** (2026-10-06), not only used for resolution, so Facts can be re-resolved after a taxonomic split.
- **Validation has two layers (2026-10-06):** the JSON Schema (shape, controlled values; runs in any standard validator) and a Gallformers dry-run import (references, IDs, qualifier targets, quotes found in the text).
- **Editing:** a batch can be edited only during import, before publishing. After publishing, a curator who disagrees adds a **Gallformers** statement (confirming or denying).
- **Re-import (`replace` mode, v3 decision 1) replaces that Source's attributions** (behind an overwrite warning) — not Facts. A Fact survives if another Source still supports it; one left with no support becomes *Unsupported* (hidden; the audit log keeps it).
- **Observations** appear only as cited evidence on a Fact. Observational data (e.g. Research Grade iNat locations) never arrives through import.
- **The format becomes a JSON Schema in the repo** (e.g. `priv/schemas/import_batch.schema.json`), with its allowed-value lists kept in sync with Gallformers' vocabulary tables (ideally generated from them).

## Format v3 decisions (full specification, from 2026-10-07)

Working toward the committed schema (`294c`). Supersede v2 where they differ.

1. **Batch modes** — every batch declares `mode`:
   - `replace` — a whole re-run of a Source (the normal pipeline case): replaces all of that Source's attributions, behind an overwrite warning.
   - `add` — new statements that leave existing attributions alone: a missed passage from a paper, a curator correction. **Gallformers batches are always `add`** — Gallformers is one Source whose statements are each their own dated entry, so replacing would wipe them all.
2. **Two batch types per Source: `taxonomy` and `gall`, taxonomy first** (Jeff, 2026-10-07). Each is validated and approved on its own; a gall batch whose references depend on a pending taxonomy batch waits ("unresolved, pending taxonomy batch X"). This splits the LLM's work too — pass 1 reads the Source for taxonomic acts, pass 2 for gall data against the updated taxonomy — smaller, more reliable tasks, mirroring the two-system architecture.
3. **The schema expresses all of taxonomy from the start;** the backend applies it in stages. Acts: new taxon, new intermediate rank, move (placement), rename/recombination, synonymy, split, lump. Phase 1 applies what today's Taxonomy already can (creation, intermediate ranks, moves, renames with alias) **editorially**, keeping Source and `name_as_written` so phase 2 can turn them into sourced Facts; splits and lumps become curator tasks until phase 2 (assigning an old concept's records to daughters is likely always curator work). Silent apply vs asking first is a review-UI choice; the backend path is the same.
4. **New Galls** may be proposed (`"new": true`), with a description as written and at least one Fact about them in the same batch; the name is derived (rule 9) and overridable at approval.
5. **The producer writes names exactly as the Source does; Gallformers resolves them** (current names plus synonyms, deterministic). A producer should not map names to IDs from a list — a wrong pick is a silent error. IDs stay optional and the validator checks they agree with the name. **An unresolved name is never treated as new**: `new` is a claim the Source makes (*sp. nov.*, *gen. nov.*, *stat. nov.*), never inferred.
6. **Every controlled value carries `as_written`** — the Source's own term beside the mapped value (e.g. `texture: woody`, as written "lignified"). It replaces a separate mapping report: reviewable, auditable, and recurring unmapped terms show where the vocabulary should grow.
7. **Shared envelope and Source block** (both batch types; Jeff, 2026-10-07):
   - Envelope: `format`, `format_version` (3), `batch_type` (`taxonomy` | `gall`), `mode`, `batch_id`, `produced_at`, `producer` — including **`model` and `instructions_version`**, so the golden set can trace drift.
   - **One `authored` date drives recency**, as `{ date: YYYY[-MM[-DD]], as_written }`. For websites it is the date of the version read: the stated last-modified date if given, otherwise the access date. (Today's `pubyear` holds strings like "1999 with ongoing revisions" or "3 June 2009, accessed 31 Dec. 2022"; 909 of 927 are a plain year.)
   - `authors`: a list of names as written, not parsed. `citation`, `title`, `identifiers` (`doi`, `url`, …), `license` (`value` from `Gallformers.Licenses` + `as_written`), `retracts`, optional `gallformers_source_id`.
   - `text`: `{ file, sha256 }`, or null with a reason (e.g. scanned, unreadable) — quotes still required but unverifiable, which review shows.
   - **Gallformers batches** use `source: { "gallformers": true }` with no bibliographic fields; each statement carries its own date and statement text.
   - Editorial fields (e.g. `datacomplete`) are not in batches.
   - **Deep links live on evidence, not the Source:** each quote has optional `page` and `url` — covering scanned-book page links (BHL, HathiTrust, archive.org) and websites with a page per species.
8. **Taxonomy batch** (Jeff, 2026-10-07):
   - `taxa`: batch-local refs with `name_as_written`, `rank`, optional `new: { status }` (the Source's own claim: *sp. nov.*, *gen. nov.*, *comb. nov.*, *stat. nov.*), optional ID.
   - **Four act kinds**, each with `id`, `stance`, evidence: **`name`** (the taxon exists with this name, rank, and `authorship` kept as written — parsing is `e2cb`, later); **`placement`** (taxon → parent; a newer placement is a move; a new intermediate rank is a taxon plus placements); **`synonymy`** (name → accepted taxon; a lump is several synonymy acts); **`split`** (taxon → daughters; only states the division — assigning existing records to daughters is curator work).
   - **A recombination composes:** placement + the new combination's `name` + the old name as a synonym — as papers state it. Phase 1 maps it to today's `reclassify_species` (genus change, rename, alias).
   - **Ranks:** family, subfamily, tribe, subtribe, genus, subgenus, section, species, subspecies, variety, form. **Nothing above family.**
   - **Plant taxa are off-limits** (rule 1: POWO plus editorial edits); the validator rejects acts on them, except the rare gall-forming plant. Hosts are still referenced in gall batches.
   - **Galls never appear in taxonomy batches, and taxonomic acts never appear in gall batches.**
9. **Gall batch** (Jeff, 2026-10-07):
   - **Galls are referenced by what identifies them**, not by Gallformers ID: `identified_by` carries the keys a Source knows — `inducer` (taxon ref), `generation`, `host` — and Gallformers resolves them to a Gall entry; ambiguous or missing → unresolved references. ID optional. A new undescribed Gall is identified by its Host plus its description as written.
   - **Generation lives in `identified_by`** (it distinguishes Gall entries); every other Trait is a Fact.
   - **Single-valued:** detachable, generation (newest wins). **Multi-valued:** all other Traits — one Fact per value; a newer value doesn't overwrite an older one; only an explicit denial withdraws.
   - **Gall aliases are common names only;** scientific names are taxon synonyms (taxonomy batches).
   - Genus-level Hosts ("*Quercus* spp.") and Inducers of undescribed Galls are taxon refs at rank genus (or family).
   - **Gallformers batches** replace `quote` with `statement: { text, stated_on }`, plus optional cited Observations.
   - **Not in batches** (editorial or derived): `undescribed` (derived from whether the Inducer is known to species), abundance, `range_confirmed`, `datacomplete`.
   - Fact kinds: relationship, qualifier, trait, range, alias, **description**.
10. **Descriptions are direct quotes only** (Jeff, 2026-10-07): a "collage" of quotes from the Source about a Gall, each verified against the text. **No summaries from producers;** if Gallformers ever shows a summary, Gallformers generates it.
11. **Phase 0: a structured document travels with the import** (Jeff, 2026-10-07). Before the taxonomy and gall passes, the Source is turned into a structured document that both passes read (not the PDF). **Format: a DoclingDocument** (JSON; [Docling](https://docling-project.github.io/docling/reference/docling_document/), open source, not science-specific): headings, paragraphs, tables, captions with page provenance; serializes losslessly to JSON. Docling converts born-digital PDFs deterministically, so the LLM may only be needed for hard scans. Plain text is derived from it; storage as before (private; public only if the license allows). **Confirm in the PoC** on 2–3 trial Sources (born-digital and scanned); if Docling's output is poor on old scans, fall back to a minimal JSON block list of our own. JSON-LD was considered and rejected as the document model (it supplies linked-data semantics, not document structure); a `@context` can be added to batches later if linked-data export (`29dc`) wants it.
    - **Evidence is anchored:** when a document exists, every quote names the document item it comes from (its reference) plus optional `page` and `url`; the validator checks the quote appears in that item. The quote stays beside the pointer deliberately — the quote is the producer's claim, the pointer says where, and a mismatch is a detectable error (a pointer alone fails silently, and a paragraph is too coarse to be evidence).
    - **Gallformers resolves and stores the exact span** (item + character offsets) at import; producers never give offsets (2026-10-07).
    - **`whole_item: true`** may replace `quote` when the evidence is the item's entire text (e.g. a descriptive paragraph); Gallformers takes the text from the document. Only with an item and a document (2026-10-07).
    - **`page` is the page as printed** (for citations); the PDF page index comes from the item's Docling provenance (2026-10-07).
    - **Package per Source:** `document.json` (phase 0), `taxonomy.json` (phase 1, if the Source states taxonomic acts), `gall.json` (phase 2). They travel together; batches are approved separately, taxonomy first. Replaces v2's `source.txt` (decision 7's `text` becomes a reference to `document.json`).
12. **`unmapped` list** (Jeff, 2026-10-07): a Source term that fits no vocabulary value is never forced into the nearest one; the Fact is left out and the term goes in the batch's optional `unmapped` list (`term`, `slot`, optional `gall`, evidence, optional `note`), so it travels with the batch for review and shows where the vocabulary should grow.
13. **Golden regression set:** the trial's Sources with reviewed, known-good JSON. Re-run them whenever the model or prompt changes and diff against the golden output, so prompt drift is measured, not discovered.

## Open items

- **Evidence (settled 2026-10-07: quote anchored to a document item, plus page and optional url — v3 decisions 7, 11).** Open: how much text a quote needs to be unambiguous within its item; Sources with no usable document.
- **Generation vocabulary** is provisional (below); aphid host-alternation phases are still open in `b5bd`. One existing entry covers "summer and autumn generations" — a Gall with two generation values, though generation is single-valued.
- **Validation beyond the schema:** e.g. a `gall_context` must be a Gall in the same batch or an existing Gall; a qualifier must point at a Relationship Fact; a `new` Gall must have at least one Fact.
- **UX for later:** unresolved references, the overwrite warning and change view, batch approve/deny.

## Draft format v2 (2026-10-05)

A batch is a directory in the bucket: `batch.json` plus the plain-text rendition (`source.txt`).

```json
{
  "format": "gallformers-import",
  "format_version": 2,
  "batch_id": "6f1c…",
  "produced_at": "2026-10-05T14:00:00Z",
  "producer": { "name": "source-ingestion", "version": "0.5.0" },

  "source": {
    "gallformers_source_id": 412,
    "kind": "publication",
    "title": "Cynipid galls of the Pacific slope",
    "authors": "Weld, L.H.",
    "authored": "1957",
    "citation": "Weld, L.H. 1957. Cynipid galls of the Pacific slope. Ann Arbor.",
    "link": "https://…",
    "license": "All Rights Reserved",
    "text": { "file": "source.txt", "sha256": "…" },
    "retracts": null
  },

  "galls": [
    { "ref": "g1", "name_as_written": "Andricus quercuscalifornicus", "gallformers_gall_id": 1234 },
    { "ref": "g2", "new": true, "name_as_written": "a small spindle gall on the midrib" }
  ],

  "taxa": [
    { "ref": "t1", "name_as_written": "Andricus quercuscalifornicus", "gallformers_taxon_id": 8102 },
    { "ref": "t2", "name_as_written": "Quercus lobata" },
    { "ref": "t3", "name_as_written": "Quercus douglasii" },
    { "ref": "t4", "name_as_written": "Torymus sp." }
  ],

  "facts": [
    { "id": "f1", "stance": "confirm", "kind": "relationship", "type": "inducer_of", "subject": "t1", "object": "g1",
      "evidence": [ { "locator": { "text_range": [10234, 10410], "page_hint": "58" }, "quote": "…produced by A. quercuscalifornicus…" } ] },

    { "id": "f2", "stance": "confirm", "kind": "relationship", "type": "host_of", "subject": "t2", "object": "g1",
      "evidence": [ { "locator": { "text_range": [10512, 10580], "page_hint": "58" } } ] },

    { "id": "f3", "stance": "deny", "kind": "relationship", "type": "host_of", "subject": "t3", "object": "g1",
      "evidence": [ { "locator": { "text_range": [12001, 12090] }, "quote": "…earlier records from Q. douglasii are misidentifications…" } ] },

    { "id": "f4", "stance": "confirm", "kind": "relationship", "type": "parasitoid_in", "subject": "t4", "object": "g1",
      "evidence": [ { "locator": { "text_range": [13010, 13200] } } ] },

    { "id": "f5", "stance": "confirm", "kind": "qualifier", "of": "f4", "qualifier": "parasitism_mode", "value": "koinobiont",
      "evidence": [ { "locator": { "text_range": [13010, 13200] } } ] },

    { "id": "f6", "stance": "confirm", "kind": "trait", "gall": "g1", "trait": "generation", "value": "agamic",
      "evidence": [ { "locator": { "text_range": [10234, 10410] } } ] },

    { "id": "f7", "stance": "confirm", "kind": "trait", "gall": "g1", "trait": "color", "value": "tan",
      "evidence": [ { "locator": { "text_range": [11020, 11064] }, "quote": "…pale tan when mature…" } ] },

    { "id": "f8", "stance": "confirm", "kind": "range", "gall": "g1", "adjustment": "include", "place_code": "US-CA",
      "evidence": [ { "locator": { "text_range": [11102, 11140] } } ] },

    { "id": "f9", "stance": "confirm", "kind": "alias", "gall": "g1", "alias_type": "common", "name": "California oak apple",
      "evidence": [ { "locator": { "text_range": [10180, 10230] } } ] }
  ]
}
```

| Part | Rule |
|---|---|
| Envelope | `format` + `format_version` let Gallformers reject formats it doesn't know; `batch_id` and `producer` are for the audit trail. |
| Source | Exactly one. `gallformers_source_id` optional; otherwise matched or created from the bibliographic fields. `kind` ∈ publication, website/database, unpublished, research data. `authored` required (YYYY, YYYY-MM, or YYYY-MM-DD). `license` from `Gallformers.Licenses`. `text` points to the plain-text rendition and its hash. `retracts` optional: a reference to the Source this one retracts. Gallformers' own Source isn't imported through a batch. |
| Galls / taxa | Declared once with a batch-local `ref`; Facts point to refs. `name_as_written` required; IDs optional. `"new": true` proposes a new Gall entry. |
| Facts | Batch-unique `id`; `stance` ∈ confirm, deny; `kind` ∈ relationship, qualifier, trait, range, alias. A Fact's identity is its natural key (`8567`), so a denial needn't match anything already published. |
| Relationship | `type` ∈ inducer_of, host_of, symbiont_of, inquiline_of, cecidophage_in, parasitoid_in, emerged_from, feeds_on, herbivore_of, successor_in, modified_form_of, alternate_generation_of, parasitoid_of, vectored_by, predator_of. `subject` / `object` refs; `gall_context` (a Gall ref) required on organism-to-organism types (parasitoid_of, vectored_by, predator_of). |
| Qualifier | `of` = the batch-local ID of the Relationship Fact it qualifies; `qualifier` ∈ required_for_formation, lethality, parasitism_mode; `value` from that qualifier's list (lethality: lethal, non-lethal; parasitism_mode: idiobiont, koinobiont, solitary, gregarious, ecto, endo; required_for_formation: true). |
| Trait | `trait` ∈ generation, detachable, plant_part, form, shape, color, texture, alignment, walls, cells, season; `value` must be an exact value from the domain doc's Trait table (generation: provisional list below). |
| Range | An adjustment to the Gall's potential range (which is computed from its Hosts and never imported). `adjustment` ∈ include, exclude; `place_code` must be a Gallformers place code (ISO-style, e.g. `US`, `US-CA`). |
| Alias | `alias_type` ∈ common, scientific; `name`. |
| Evidence | At least one per Fact. **`quote` required for literature, plus `page_hint`** (2026-10-06 — replaces the `text_range` locators in the example above); optional `observations`: structured references (`{ "provider": "inaturalist", "id": "12345" }`). |
| Not included | Editorial data (abundance, photos, names), derived data (theoretical range, hyperparasitism), observational data, and — until phase 2 — taxonomic Facts. |

## Generation vocabulary (provisional, 2026-10-05)

agamic, sexual, spring, summer, autumn.

Rust spore stages (aecial, telial) are deliberately excluded — rusts are likely to be dropped. Aphid host-alternation phases are still open (`b5bd`).
