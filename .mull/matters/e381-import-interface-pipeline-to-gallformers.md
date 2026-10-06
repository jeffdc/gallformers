---
status: raw
created: 2026-10-03
updated: 2026-10-05
epic: taxonomy
relates: [1121, 8567]
---

# Import interface: pipeline to Gallformers

The contract by which any ingestion pipeline delivers data into Gallformers. It is designed fresh from the domain model ([`docs/domain/domain-model.md`](../../docs/domain/domain-model.md)) and the Sources–Facts design in matter `8567`; the existing pipeline work predates the greenfield design and is not a constraint. The pipeline itself is a separate workstream (`7fda`, `db6f`) that only has to honor this contract.

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
- **Plain-text rendition:** the pipeline produces a plain-text version of the Source. Gallformers stores it privately; it is shown publicly only if the license allows.
- **Editing:** a batch can be edited only during import, before publishing. After publishing, a curator who disagrees adds a **Gallformers** statement (confirming or denying).
- **Re-import replaces that Source's attributions** (behind an overwrite warning) — not Facts. A Fact survives if another Source still supports it; one left with no support becomes *Unsupported* (hidden; the audit log keeps it).
- **Observations** appear only as cited evidence on a Fact. Observational data (e.g. Research Grade iNat locations) never arrives through import.
- **The format becomes a JSON Schema in the repo** (e.g. `priv/schemas/import_batch.schema.json`), with its allowed-value lists kept in sync with Gallformers' vocabulary tables (ideally generated from them).

## Open items

- **Evidence and locators (needs a real design pass).** Locators point into the stored plain-text rendition (e.g. character ranges), with an optional page hint for humans. Open: how the text is identified (a file beside the batch plus a content hash), what happens to locators when a Source is re-imported with a new rendition, and how quotes relate to ranges.
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
| Evidence | At least one per Fact. `locator` required for literature (shape open — see above); optional short `quote`; optional `observations`: structured references (`{ "provider": "inaturalist", "id": "12345" }`). |
| Not included | Editorial data (abundance, photos, names), derived data (theoretical range, hyperparasitism), observational data, and — until phase 2 — taxonomic Facts. |

## Generation vocabulary (provisional, 2026-10-05)

agamic, sexual, spring, summer, autumn.

Rust spore stages (aecial, telial) are deliberately excluded — rusts are likely to be dropped. Aphid host-alternation phases are still open (`b5bd`).

