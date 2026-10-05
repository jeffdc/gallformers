---
status: dropped
created: 2026-09-13
updated: 2026-10-04
epic: taxonomy
relates: [b5bd, e381, 8567]
needs: [4dcd, 53cb, f465]
---

# Taxonomy — greenfield domain model

> **Status: not pursued (dropped 2026-10-04).** This direction mirrored iNaturalist as the taxonomy and kept Gallformers out of taxonomic authority. Jeff and Adam chose the alternative instead: **Gallformers owns its taxonomy**, with every taxonomic fact sourced, built as a separate system from the gall system — matter `8567`. Adam's reasoning: sourced taxonomic facts are required either way, the curation burden exists whether work goes into iNat or Gallformers, and handling it internally keeps it under our control and open to LLM tooling. Kept for history: the interview record and the reasoning behind the iNat route. The gall side of the model carried forward; `docs/domain/domain-model.md` now reflects the owned-taxonomy direction.

Rebuild Gallformers' domain model from scratch around galls, then work out how to move the existing data and application onto it.

**The model is defined in [`docs/domain/domain-model.md`](../../docs/domain/domain-model.md).** This matter tracks how we got there and what's still open; migration details live in matter `b5bd`, the import interface in matter `e381`. It does not define the model.

History: PM-led interview with Jeff (2026-09-30); Jeff's and Adam's answers to the follow-up questions and a relationship brainstorm backed by prior-art research (2026-10-01); domain-model document drafted (2026-10-02). Sent to Adam for review.

## Open questions

- **Traits with host context — must be decided before the plan is complete.** Can a trait (plant part, timing, minor form) be scoped to a host ("petiole on *Q. rubra*, leaf on *Q. velutina*")? Leaning **no**: the complexity isn't worth it; real host-dependent differences go in a Note or justify a separate gall entry.
- **Relationship-type list.** Review the full set of edge types and modifiers (including the old role list) in a separate session.
- **Name authorship — likely eliminate; needs Adam's buy-in** (he asked for the feature). If kept, it is editorial, never a fact, so the precept "facts are about galls" holds without exception. Research (2026-10-02): iNat has no authorship anywhere (database, API, export). Plant authorship is already in our WCVP data (`taxon_authors`); inducer authorship would be manual.
- **iNat taxonomic changes.** How renames, reclassifications, merges, splits, and deactivations flow into linked galls and derived names. Very complex; needs its own design. Facts for the discussion (research 2026-10-02):
  - iNat change types: swap (1→1, rename/recombination), merge (many→1), split (1→many), drop (no successor), stage (activation only). Statuses include draft and committed.
  - Taxon IDs are never reused. A changed taxon becomes `is_active: false` and lists its successors in `current_synonymous_taxon_ids`; successors can chain.
  - A swap can be followed automatically; **a split needs a curator** to choose which successor each gall's link goes to.
  - Feed: `www.inaturalist.org/taxon_changes.json`, filterable by taxon or ancestor, 30 per page newest first, no date filter. Detection: re-fetch our taxon IDs weekly in batches (~25–50 calls) and look for inactive taxa; use the feed as the audit log.
  - Already affecting galls: on 2026-08-06 iNat committed 30 swaps of *Cynips* species into *Nubilantron*.
  - Mapping results and caching approach: matter `b5bd`.
- **Release sequencing.** Migration, then backscan, then release. **Release is sequenced with the backscan**: the two are tied together, so release waits on the pipeline workstream. Contingency if the pipeline work fails: not yet planned (the fallback would be releasing on migrated, unattributed data). Needs its own sequencing plan.
- **Durable references.** Retained (see decisions); the details for merges, splits, and renames are still to design.
- **Free-text description.** A mix of sourced, editorial, and generated. Deferred until closer to implementation.

## Adjacent areas — design before implementing

- **Auditing:** who changed what, and when, across all data. This is operational history, distinct from Sources (why a fact is true). Related: Note edit history with author attribution. See `ede2`.

## Next steps

1. Decide traits with host context (definitive answer required).
2. Review the relationship-type list and modifiers (separate session).
3. Design iNat taxonomic change handling.
4. Domain-model document: drafted at `docs/domain/domain-model.md`. CLAUDE.md points to it. Remaining: incorporate Adam's review, commit.
5. Design the import interface: the contract by which any pipeline delivers a batch into Gallformers (matter `e381`).
6. Design the schema from the domain-model document.
7. Write the release sequencing plan (migration → backscan → release), then estimate. Migration details: matter `b5bd`.

## Scope boundary

- **In this effort:** the domain model, the schema, the migration, and the **import interface** — the technical contract by which a pipeline gets data into Gallformers.
- **Separate workstream:** building the ingestion pipeline itself (`7fda`, `db6f`). It only has to honor the import interface. The existing pipeline work (`services/source-ingestion/`, `lib/gallformers/ingestion_pipeline/`, `priv/schemas/gall_record.json`) predates the greenfield design: it is legacy, not a constraint. The interface is designed fresh from the domain model, and the pipeline adapts to it.
- **Later work:** the UX for reviewing and handling imported batches (batch approve/deny, curator edits afterward).

## Import interface

The contract by which any pipeline delivers data into Gallformers: decisions, open items, and the draft format live in matter `e381`.

## Details

### Migration

All migration details — work items, notes, and the data inventory — live in matter `b5bd` (Taxonomy migration).

### Prior art

Research summary (2026-10-01):

- **Typed, directed edges with declared inverses** are the norm: the [OBO Relation Ontology](http://purl.obolibrary.org/obo/ro.obo) (e.g. *parasitoid of* RO:0002208 / *has parasitoid* RO:0002209, *is vector for* RO:0002459, *creates habitat for* RO:0008505), [GloBI](https://api.globalbioticinteractions.org/interactionTypes) (49 types mapped to RO), Darwin Core ResourceRelationship, and [TaxonWorks](https://rdoc.taxonworks.org/BiologicalRelationship.html) (name / inverted name).
- **Exchange formats are strictly pairwise.** The [Darwin Core data package](https://github.com/gbif/dwc-dp/blob/master/dwc-dp/table-schemas/organism-interaction.json) says "pairwise interactions must be used to represent multi-organism interactions." Multi-party facts are tied together by a shared event, grouped edges (TaxonWorks "citable foodweb"), or a reified relationship ([W3C n-ary note](https://www.w3.org/TR/swbp-n-aryRelations/)). No database found models ambrosia galls as one multi-party fact.
- **Context** (life stage, body part, location) attaches to an edge or event, not the type. No standard has a host-plant scope field.
- **RO lacks** inquiline-of, induces-gall-on, and symbiont-of; GloBI's pattern is local types with an optional RO identifier. Idiobiont/koinobiont and solitary/gregarious aren't in RO; the Universal Chalcidoidea Database stores parasitoid type as qualifier codes.
- **Ambrosia galls**: fungal symbionts deposited with the eggs ([Rohfritsch 2008](https://onlinelibrary.wiley.com/doi/abs/10.1111/j.1570-7458.2008.00726.x)).

## Related matters

Reconcile against this model: `2cb2` (multi-species gall model), `86e7` (name builder), `e2cb` (authorship), `d108` (hierarchy), `e1d2` (exact iNat taxon refs), `1832` (taxon pages), `53cb` (genus-level hosts), `0a58` (generation field), `3e8c`/`5c56` (merge/split), `f49a` (taxonomic history), `1374` (DNA), `7fda`/`db6f` (ingestion), `ede2` (audit trail), `29dc` (data interoperability — RO-mapped edges help here), `4dcd` (portfolio).


## Alternative direction

This matter's direction mirrors iNaturalist as the taxonomy. An alternative — Gallformers owns its taxonomy, with sourced taxonomic facts, built as a separate system and delivered in phases — is recorded in matter `8567`. The two are options; neither is chosen.
