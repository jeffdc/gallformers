---
status: raw
created: 2026-09-13
updated: 2026-10-01
epic: taxonomy
needs: [4dcd, 53cb, f465]
---

# Taxonomy — greenfield domain model

Rebuild Gallformers' domain model from scratch around galls, then work out how to move the existing data and application onto it. This matter holds the model from a PM-led interview with Jeff (2026-09-30), Jeff's and Adam's answers to the follow-up questions, and a relationship brainstorm backed by prior-art research (2026-10-01). It replaces all earlier drafts.

## The most important decisions

1. **Gallformers is not a taxonomic authority. Facts are about galls.** Everything else rests on this. Taxonomy, observations, and barcodes belong to others; we reference and cache them. The complexity lives in the gall and its relationships.
2. **Taxonomy comes from iNaturalist**, held in a local cache. Gallformers never creates taxa; an undescribed species is linked at genus level, with a Note explaining it.
3. **A gall entry is one distinct, repeatable gall form plus its community** (inducer, hosts, inquilines, parasitoids, …). Curators decide where one entry ends and another begins. Galls of different species are different entries, even when they can't be told apart in the field.
4. **Every fact is attributed to a Source**: a paper, book, website, available unpublished work, or Gallformers Note. That is how researchers trust the data. Single observations and barcodes are not Sources and not species-level facts. Withdrawn facts stay visible.
5. **Relationships are typed two-party edges centered on the gall.** Each has a type with an inverse label, optional modifiers, an optional gall context, and its own Sources — the same pattern as the OBO Relation Ontology, GloBI, and Darwin Core. The gall entry ties related edges together.
6. **A gall has at most one inducer**, at any rank. Uncertainty lives in the Source text, not in the data model.
7. **Two ranges:** a theoretical range derived from the hosts (used by the ID tool), and an observed range made of sourced facts.
8. **The ingestion pipeline is built as part of this effort and runs outside the site.** Its output is imported, approved or denied as a whole batch, then published. All existing Sources are run through it before release, so released data carries its attribution.

## Open questions

- **Traits with host context — must be decided before the plan is complete.** Can a trait (plant part, timing, minor form) be scoped to a host ("petiole on *Q. rubra*, leaf on *Q. velutina*")? Leaning **no**: the complexity isn't worth it; real host-dependent differences go in a Note or justify a separate gall entry.
- **Relationship-type list.** Review the full set of edge types and modifiers (including the old role list) in a separate session.
- **iNat taxonomic changes.** How renames, reclassifications, merges, splits, and deactivations flow into linked galls and derived names. Very complex; needs its own design.
- **Release sequencing.** Pipeline, then migration, then backscan, then release. Needs its own sequencing plan.
- **Durable references.** Retained (see decisions); the details for merges, splits, and renames are still to design.
- **Free-text description.** A mix of sourced, editorial, and generated. Deferred until closer to implementation.

## Adjacent areas — design before implementing

- **Auditing:** who changed what, and when, across all data. This is operational history, distinct from Sources (why a fact is true). Related: Note edit history with author attribution. See `ede2`.

## Next steps

1. Decide traits with host context (definitive answer required).
2. Review the relationship-type list and modifiers (separate session).
3. Design iNat taxonomic change handling.
4. Turn the vocabulary and diagram into a maintained domain-model document for agents and humans.
5. Design the schema from the vocabulary.
6. Write the release sequencing plan (pipeline → migration → backscan → release), then estimate.

## Details

### Who it's for

- **Academics** (primary) want to trust the data, get new findings in, and search more deeply — e.g. "do we have a gall matching this barcode?" or "what facts come from Weld 1956?"
- **Operators/curators** (primary) want to maintain data without today's tedious, error-prone manual process.
- **Casual users** (ID, following a link) already have what they need. **Rule: don't make it worse.**

### All decisions

**Galls**

1. A **gall** is a novel structure on a plant, induced by another organism in a repeatable way (not a damage response). A **gall entry** is one distinct, repeatable gall form plus its community (hosts, inducer, inquilines, parasitoids, …). Boundaries are curator judgment; see *Gall entry boundaries* below.
2. **Galls of different species are different entries**, even when indistinguishable in the field (e.g. 839/4227).
3. **Generation** (agamic/sexgen) is a property of the gall. Each generation is its own entry.
4. **Gall names** are derived by default (inducer + generation, plus host/form for unknowns), can be overridden by a curator, and must be **unique**.
5. When an unknown gall is later identified, a curator decides whether to merge it into an existing entry or keep it separate.
6. **Durable references are retained.** Old gall URLs and Gallformers Codes keep working through renames, merges, and splits.
7. **One ID sequence shared by galls and taxa.** Galls keep their current IDs, plant taxa keep theirs, and new galls and taxa draw from the same sequence, so a gall and a taxon never share a number. See *Migration notes*.

**Taxa**

8. **iNaturalist is the authority for all taxonomy**, plants included. Gallformers keeps a **local cached copy** so it never depends on iNat being up.
9. **Gallformers never creates taxa.** An undescribed species is linked at genus level; "this is a distinct undescribed species" lives in a Note.
10. **Name authorship:** iNat doesn't track it. Authorship tracking may be allowed, entered manually; it may be more work than it's worth.
11. **Species synonymy works as today**, fitted into the new model. Gall aliases and common names are ours, as today. When an unknown gall is linked to a species, its old name becomes an alias.
12. **Gallformers' phylogeny view is editorial, not fact.** Gallformers may want to show its own opinion of how the phylogeny is shaping up — regrouping across genera and including unknowns — for visualization, possibly built outside the app from a database snapshot. It is independent of the iNat taxonomy and never modifies it. It needs no Sources and no tables now; durable IDs for taxa and galls (galls stand in for undescribed species) keep the door open.

**Facts and Sources**

13. **Every fact is attributed to at least one Source.** That is how academics trust the data.
14. **Sources** are published papers/books, websites/databases, unpublished but available works, and **Gallformers Notes**. A single observation, specimen record, or personal communication is **not** a Source, but can be mentioned in a Note.
15. A **Gallformers Note** is a list of statements, each attributed to a Gallformers author and each tied to a tracked fact. Statements can be superseded. Summaries may be generated for at-a-glance reading.
16. **A barcode is an observation** of an individual. It can support a fact; it is never a species- or gall-level fact.
17. **Uncertainty lives in the Source text**, not in the data model. There are no suspected/confirmed link types.
18. **Withdrawn facts are kept and publicly visible**, with the reason and the withdrawing Source (e.g. "reported by Weld 1956; withdrawn per Smith 2026").

**Relationships**

19. **Three kinds of relationship**, by owner: *cached* (taxonomy parent links — iNat's), *asserted* (everything below — ours, sourced), and *opinion* (the phylogeny view — ours, editorial). Only asserted relationships are modeled as edges here.
20. **An asserted relationship is a typed two-party edge**: a type with an inverse label (and an RO identifier where one exists), optional **modifiers**, an optional **gall context**, and its own Sources. N-party facts are expressed as several edges around the gall; see *Relationship cases*.
21. **Edge kinds:**
    - **Taxon → gall:** inducer of, cecidophage in, symbiont of, parasitoid in (target unknown), feeds on, successor in (inverse: "habitat for").
    - **Plant → gall:** host of (inverse: "induced on").
    - **Gall → gall:** modified form of, alternate generation of, looks like.
    - **Taxon → taxon, always with a gall context:** parasitoid of, vectored by, predator of.
22. **At most one inducer per gall**, at any rank. No inducer link means unknown. Competing candidates map to their shared higher taxon (e.g. the genus). A fungus required for gall formation is a required symbiont, not a second inducer.
23. **Hyperparasitism is derived** from chains of "parasitoid of" edges, not stored.
24. **Parasitism**: a small set of types mapped to RO; mode (idiobiont/koinobiont, solitary/gregarious, ecto/endo) as modifiers.
25. **Gall-to-gall links:** alternate generations are derived (same inducer species); others, such as modified forms, are explicit.
26. **Observation → gall links are stored.** Barcode search runs barcode → observation → gall; the sequence matching itself uses external tools.
27. **Edge types are a fixed list**, changed deliberately.

**Ranges**

28. **Two ranges.** The **theoretical range** is derived from the gall's hosts' distributions (WCVP/POWO). The **observed range** is a set of sourced range facts. Genus-level hosts contribute nothing to the theoretical range.
29. **The ID tool uses the theoretical range.** An observed-range filter may be added later.

**Data intake**

30. **The LLM ingestion pipeline is built as part of this effort** and runs outside the Gallformers server. Its output enters through an import process.
31. **Import and publish are separate steps.** Once imported, the data belongs to the Gallformers DB but isn't live until published.
32. **Imports are approved or denied as a whole batch.** There are too many facts for per-fact review. Curators keep control by editing individual facts afterward.
33. **All existing Sources go through the pipeline (the backscan) before release.** That checks current data for errors and gives legacy facts their Source attribution, so data never sits in a partially attributed state.
34. **Source texts are never stored in the database or exposed.** Many are copyrighted. Full texts may sit in a private S3 bucket for processing only. Short supporting quotes may be stored.

**Scope**

35. **Non-galls are not part of the data model.** Gall lookalikes are handled only as an educational article.

### Relationship cases

`X —type→ Y` is an edge, `[ctx G]` a gall context, `{…}` a modifier.

| Case | Edges |
|---|---|
| S induces G on H | `S —inducer of→ G`; `H —host of→ G` |
| S1 modifies G2 (induced by S2) to form G1 | `S1 —inducer of→ G1`; `G1 —modified form of→ G2`; `S2 —inducer of→ G2` |
| S1 and S2 both required to form G1 (midge + fungus) | `S1 —inducer of→ G1`; `S2 —symbiont of→ G1 {required for formation}`; `S2 —vectored by→ S1 [ctx G1]` |
| S1 parasitizes S2 in G2 | `S1 —parasitoid of→ S2 [ctx G2]`; target unknown: `S1 —parasitoid in→ G2` |
| S1 parasitizes S2, which parasitizes S3, in G3 | `S2 —parasitoid of→ S3 [ctx G3]`; `S1 —parasitoid of→ S2 [ctx G3]`; S1's hyperparasitism is derived |
| S1 feeds in G2 without killing S2 or changing its form (cecidophagy) | `S1 —cecidophage in→ G2 {non-lethal}` |
| S1 eats G2 | `S1 —feeds on→ G2`; eating the occupant: `S1 —predator of→ S2 [ctx G2]` |
| S1 moves into vacated G2 (successor) | `S1 —successor in→ G2` (inverse: G2 is habitat for S1) |

### Prior art

Research summary (2026-10-01):

- **Typed, directed edges with declared inverses** are the norm: the [OBO Relation Ontology](http://purl.obolibrary.org/obo/ro.obo) (e.g. *parasitoid of* RO:0002208 / *has parasitoid* RO:0002209, *is vector for* RO:0002459, *creates habitat for* RO:0008505), [GloBI](https://api.globalbioticinteractions.org/interactionTypes) (49 types mapped to RO), Darwin Core ResourceRelationship, and [TaxonWorks](https://rdoc.taxonworks.org/BiologicalRelationship.html) (name / inverted name).
- **Exchange formats are strictly pairwise.** The [Darwin Core data package](https://github.com/gbif/dwc-dp/blob/master/dwc-dp/table-schemas/organism-interaction.json) says "pairwise interactions must be used to represent multi-organism interactions." Multi-party facts are tied together by a shared event, grouped edges (TaxonWorks "citable foodweb"), or a reified relationship ([W3C n-ary note](https://www.w3.org/TR/swbp-n-aryRelations/)). No database found models ambrosia galls as one multi-party fact.
- **Context** (life stage, body part, location) attaches to an edge or event, not the type. No standard has a host-plant scope field.
- **RO lacks** inquiline-of, induces-gall-on, and symbiont-of; GloBI's pattern is local types with an optional RO identifier. Idiobiont/koinobiont and solitary/gregarious aren't in RO; the Universal Chalcidoidea Database stores parasitoid type as qualifier codes.
- **Ambrosia galls**: fungal symbionts deposited with the eggs ([Rohfritsch 2008](https://onlinelibrary.wiley.com/doi/abs/10.1111/j.1570-7458.2008.00726.x)).

### Vocabulary

| Term | Definition |
|---|---|
| **Gall** | A novel structure on a plant, induced by another organism in a repeatable way. Not a damage response. |
| **Gall entry** | One distinct, repeatable gall form plus its community. Boundaries are curator judgment. |
| **Generation** | Agamic or sexgen; a property of a gall. |
| **Taxon** | An organism group at any rank, from iNaturalist, held in a local cache. Never created by Gallformers. |
| **Fact** | A statement attributed to one or more Sources: relationships, traits, observed-range entries. |
| **Relationship** | An asserted, sourced, typed two-party edge. Kinds: taxon → gall, plant → gall, gall → gall, taxon → taxon (with gall context), observation → gall. |
| **Relationship type** | From a fixed list. Has a direction, an inverse label, and an RO identifier where one exists. |
| **Modifier** | A qualifier on a relationship: lethal/non-lethal, required for formation, parasitism mode, … |
| **Gall context** | The gall a taxon → taxon relationship happens in. Required on every taxon → taxon edge. |
| **Inducer link** | The relationship *inducer of*. At most one per gall, any rank. |
| **Host link** | Relationship: plant taxon P *host of* gall G. Genus-level = host unidentified beyond genus. |
| **Trait** | Fact: morphology, plant part, phenology/season. Gall-level (host context undecided). |
| **Observed range** | Range facts (gall G occurs in place X), each sourced. |
| **Theoretical range** | Derived from the hosts' WCVP/POWO distributions. Used by the ID tool. |
| **Observation** | A single record of an individual: an iNat observation, a specimen record, a barcode. External, not a Source; can be linked to a gall and mentioned in a Note. |
| **Source** | A published paper/book, website/database, unpublished but available work, or Gallformers Note. |
| **Gallformers Note** | A Source made of attributed, supersedable statements, each tied to a fact. |
| **Withdrawn fact** | A fact no longer believed true. Kept and publicly visible with the reason and withdrawing Source. |
| **Phylogeny view** | Gallformers' editorial opinion of phylogeny, independent of the taxonomy. Not facts. |
| **Import / Publish** | Import brings a pipeline batch into the DB, unpublished. The batch is approved or denied as a whole; publish makes it live. |
| **Gall name** | Derived, overridable, unique. |
| **Editorial** | Needs no Source: name override, photos and their order, data-complete flag, review state, the phylogeny view. |

### Diagram

```text
                     ┌─────────────── SOURCE ───────────────┐
                     │ paper · book · website/db ·           │
                     │ unpublished work · Gallformers Note   │
                     └──────────────────┬────────────────────┘
                                        │ attributes every fact
                                        ▼
  TAXON (iNat cache) ──── inducer of / cecidophage in / ────┐
    │ parent              symbiont of / parasitoid in /      │
    │                     feeds on / successor in            │
    │ ── parasitoid of / vectored by / predator of ──► TAXON │
    │        (always with a gall context)                    │
  TAXON (plant) ──────────── host of ────────────────────────┤
    │ distribution (WCVP)                                    ├── GALL [generation, name, traits]
    ▼                                                        │     └── modified form of / alternate generation of /
  PLACE ◄──────────────── observed range ────────────────────┤         looks like ──► GALL
  OBSERVATION (external) ◄──── observation link ─────────────┘
      ▲
      └── mentioned by Gallformers Note statements
```

### Gall entry boundaries

| Case | Answer |
|---|---|
| Agamic vs. sexgen of one species | Two entries |
| One species, same gall on many hosts | One entry |
| One species, form varies by plant part or host | Separate entries only if truly morphologically different (curator judgment) |
| Two species, indistinguishable galls, same hosts (839/4227) | Two entries |
| Unknown inducer, gall on a different host from a lookalike | New entry |
| Unknown inducer, different region | Depends: adjacent regions no (Q. alba in VA vs. NC); widely disjunct populations possibly |
| Unknown later identified as species X | Curator decides: merge if the same form, otherwise keep separate and link to X |

### Migration notes

- **Order: build the pipeline, migrate, backscan, then release.** Legacy data is migrated as-is so the new system runs, the backscan attributes it, and only then is it released.
- **IDs.** Today galls and plants share the `species` ID sequence; higher taxa have a separate `taxonomy` ID sequence. After the split:
  - Galls keep their species IDs, so `/gall/:id` and the API's `/galls/:id` stay valid.
  - Plant taxa keep their species IDs, so `/host/:id` stays valid.
  - Inducer taxa get new IDs: one inducer can merge several old rows (e.g. its agamic and sexgen galls), and the gall keeps the old number.
  - Higher taxa get new IDs; their old IDs collide with species IDs. Only the legacy `/taxonomy/:id` redirect needs a crosswalk — genus and family pages are addressed by name.
  - Going forward, galls and taxa draw from one shared Postgres sequence starting above today's highest species ID.
- **Today's genus placeholder plants** ("*Quercus* spp.") become genus-level host links. They carry no range data today, and none is wanted.
- **Today's stored gall range** counts as observed range only once it's backed by Sources.
- **The ID tool changes from "stored range, else host union" to the theoretical range.** That may broaden some results; verify it doesn't make ID worse.
- **Plants move from WCVP/POWO identity to the iNat taxonomy cache.** WCVP stays as the source of plant distributions.

## Related matters

Reconcile against this model: `2cb2` (multi-species gall model), `86e7` (name builder), `e2cb` (authorship), `d108` (hierarchy), `e1d2` (exact iNat taxon refs), `1832` (taxon pages), `53cb` (genus-level hosts), `0a58` (generation field), `3e8c`/`5c56` (merge/split), `f49a` (taxonomic history), `1374` (DNA), `7fda`/`db6f` (ingestion), `ede2` (audit trail), `29dc` (data interoperability — RO-mapped edges help here), `4dcd` (portfolio).

