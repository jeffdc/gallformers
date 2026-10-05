---
status: raw
created: 2026-10-03
updated: 2026-10-04
epic: taxonomy
relates: [1121, 8567]
---

# Import interface: pipeline to Gallformers

The contract by which any ingestion pipeline delivers data into Gallformers. It is designed fresh from the domain model ([`docs/domain/domain-model.md`](../../docs/domain/domain-model.md)); the existing pipeline work predates the greenfield design and is not a constraint. The pipeline itself is a separate workstream (`7fda`, `db6f`) that only has to honor this contract. Design context: matter `8567` (owned taxonomy; taxonomy and gall systems).

## Decisions

- **Delivery:** the pipeline writes a batch to the private S3 bucket; an Oban job imports it as unpublished. A curator upload on an admin page is a UI wrapper around the same path.
- **Unit:** one Source per batch. The Source is the replacement key.
- **The producer is responsible for clean data.** Every controlled value must be exact and is enforced by the schema: trait values, generation terms, relationship types, modifiers, alias types, license, Source kind, place codes. A batch with an unknown value is rejected, never fixed up in the admin tool. **The only Gallformers-side work is ID lookup** for entities (galls, taxa, Sources).
- **Entity references:** every gall and taxon reference carries `name_as_written`; IDs (Gallformers gall ID, Gallformers taxon ID, Gallformers Source ID) are optional. The pipeline may start with none and grow stronger; Gallformers resolves every reference itself, against its own taxonomy and galls, and validates any ID it is given. A batch can propose a new gall entry through a batch-local reference.
- **Taxonomic Facts (phase 2):** once the taxonomy system exists, a batch can also carry taxonomic Facts (name, authorship, rank, placement, synonymy) and propose new taxa. Batch-local references then span both systems, and taxonomic Facts are applied before gall Facts.
- **License** uses exactly the `Gallformers.Licenses` list: Public Domain / CC0, CC-BY, CC-BY-SA, CC-BY-NC, CC-BY-NC-SA, CC-BY-ND, CC-BY-NC-ND, All Rights Reserved.
- **Plain-text rendition:** the pipeline produces a plain-text version of the Source. Gallformers stores it privately; it is shown publicly only if the license allows (a future feature might link facts to the text on the site — not designed now).
- **Withdrawals** can ride in a batch ("the earlier record of X is wrong"). A withdrawal names its target by content (gall, fact, cited earlier Source), not by ID; it takes effect only if a matching published fact exists, otherwise it is recorded with no effect.
- **Editing:** a batch's facts can be edited only during import, before publishing. After publishing, a curator who disagrees adds a Fact attributed to the **Gallformers** Source (and can withdraw the wrong one).
- **Re-import replaces** that Source's facts (behind an overwrite warning). It fixes the extraction; dropped facts are removed quietly and kept in the audit log, not shown as withdrawn.
- **Observation links** are out of v1.
- **The format becomes a JSON Schema in the repo** (e.g. `priv/schemas/import_batch.schema.json`), with its allowed-value lists kept in sync with Gallformers' vocabulary tables (ideally generated from them).

## Open items

- **Evidence and locators (needs a real design pass).** Sources exist in many digital and print versions, so page numbers aren't stable. Direction: locators point into the stored plain-text rendition (e.g. character ranges), with an optional page hint for humans. Open: how the text is delivered and identified (e.g. a file beside the batch plus a content hash), what happens to locators when a Source is re-imported with a new rendition, and how quotes relate to ranges.
- **Withdrawal matching:** what "matching published fact" means precisely.
- **Validation beyond the schema:** e.g. a `gall_context` that must be a gall in the same batch or an existing gall; a `new` gall must have at least one fact.
- **UX for later:** unresolved references, the overwrite warning and change view, batch approve/deny.

## Draft format v1 (revised 2026-10-03)

A batch is a directory in the bucket: `batch.json` plus the plain-text rendition (`source.txt`).

```json
{
  "format": "gallformers-import",
  "format_version": 1,
  "batch_id": "6f1c…",
  "produced_at": "2026-10-03T14:00:00Z",
  "producer": { "name": "source-ingestion", "version": "0.4.2" },

  "source": {
    "gallformers_source_id": 412,
    "kind": "publication",
    "title": "Cynipid galls of the Pacific slope",
    "authors": "Weld, L.H.",
    "year": 1957,
    "citation": "Weld, L.H. 1957. Cynipid galls of the Pacific slope. Ann Arbor.",
    "link": "https://…",
    "license": "All Rights Reserved",
    "text": { "file": "source.txt", "sha256": "…" }
  },

  "galls": [
    { "ref": "g1", "name_as_written": "Andricus quercuscalifornicus", "gallformers_gall_id": 1234 },
    { "ref": "g2", "new": true, "name_as_written": "a small spindle gall on the midrib" }
  ],

  "taxa": [
    { "ref": "t1", "name_as_written": "Andricus quercuscalifornicus", "gallformers_taxon_id": 8102 },
    { "ref": "t2", "name_as_written": "Quercus lobata" }
  ],

  "facts": [
    { "id": "f1", "kind": "relationship", "type": "inducer_of", "subject": "t1", "object": "g1",
      "evidence": [ { "text_range": [10234, 10410], "page_hint": "58", "quote": "…produced by A. quercuscalifornicus…" } ] },

    { "id": "f2", "kind": "relationship", "type": "host_of", "subject": "t2", "object": "g1",
      "evidence": [ { "text_range": [10512, 10580], "page_hint": "58" } ] },

    { "id": "f3", "kind": "trait", "gall": "g1", "trait": "generation", "value": "agamic",
      "evidence": [ { "text_range": [10234, 10410] } ] },

    { "id": "f4", "kind": "trait", "gall": "g1", "trait": "color", "value": "tan",
      "evidence": [ { "text_range": [11020, 11064], "quote": "…pale tan when mature…" } ] },

    { "id": "f5", "kind": "observed_range", "gall": "g1", "place_code": "US-CA",
      "evidence": [ { "text_range": [11102, 11140] } ] },

    { "id": "f6", "kind": "alias", "gall": "g1", "alias_type": "common", "name": "California oak apple",
      "evidence": [ { "text_range": [10180, 10230] } ] }
  ],

  "withdrawals": [
    { "id": "w1", "reason": "Host record based on a misidentified oak.",
      "target": { "gall": "g1", "fact": { "kind": "relationship", "type": "host_of", "subject_name": "Quercus douglasii" },
                  "cited_source": { "citation": "Kinsey 1922", "gallformers_source_id": null } },
      "evidence": [ { "text_range": [12001, 12090] } ] }
  ]
}
```

| Part | Rule |
|---|---|
| Envelope | `format` + `format_version` let Gallformers reject formats it doesn't know; `batch_id` and `producer` are for the audit trail. |
| Source | Exactly one. `gallformers_source_id` optional; otherwise matched or created from the bibliographic fields. `kind` ∈ publication, website/database, unpublished, research data (from pending research). `license` from `Gallformers.Licenses`. `text` points to the plain-text rendition and its hash. Gallformers' own Source isn't imported through a batch. |
| Galls / taxa | Declared once with a batch-local `ref`; facts point to refs. `name_as_written` required; IDs optional. `"new": true` proposes a new gall entry. |
| Facts | Batch-unique `id`; `kind` ∈ relationship, trait, observed_range, alias. |
| Relationship | `type` from the system catalog; `subject` / `object` refs; optional `modifiers` (catalog values); `gall_context` required on taxon-to-taxon types. |
| Trait | `trait` ∈ generation, color, shape, texture, walls, cells, alignment, form, plant_part, season, detachable; `value` must be an exact vocabulary value. |
| Observed range | `place_code` must be a Gallformers place code (ISO-style, e.g. `US`, `US-CA`). |
| Alias | `alias_type` ∈ common, scientific; `name`. |
| Evidence | At least one per fact. Locator design is open (see above); the draft uses a range into `source.txt`, an optional page hint, and an optional short quote. |
| Withdrawals | Target named by content plus the cited earlier Source; applied only if a matching published fact exists. |
| Not included | Editorial data (abundance, photos, names), derived data (theoretical range, hyperparasitism), observation links, and — until phase 2 — taxonomic Facts. |
