---
status: raw
created: 2026-02-14
updated: 2026-10-24
epic: gall-traits
relates: [85c0]
---

# GallOnt trait vocabulary integration

Root matter for the gall-traits epic. Connects GF's trait system to the GallOnt ontology and Prior Lab scoring work, enabling a cascade of features from illustrated glossary to external data ingest.

## Context

GallOnt is a 394-term formal ontology for gall phenotypes (v2024-04-19, Andrew Deans lab). The Prior Lab (Forbes) scores NA oak gall phenotypes using GallOnt vocabulary, with GF as a primary data source. Both systems describe the same domain with different vocabularies. Connecting them benefits all three.

**GallOnt**: GitHub adeans/gallont, OWL at purl.obolibrary.org/obo/gallont.owl, OLS JSON API at ebi.ac.uk/ols4/api/ontologies/gallont/terms, paper at bdj.pensoft.net/article/128585/. English + Spanish. iNat observation links in OBO seeAlso fields — nearly every term has a photo example. Local copies: docs/ontology/gallont.obo, docs/ontology/gallont.owl.

**Prior Lab protocols**: Two dataset levels — "average" (species/generation morphotype consensus) and "variation" (population-level across hosts/regions). 20 scoring dimensions, richly illustrated. More granular than GF in: internal tissue (7 types vs GF's walls), surface texture (15+ values), pilosity as separate axis, two-level location hierarchy, quantitative size, spatial pattern as own axis, color patterns distinct from base colors, month-level phenology.

**Current GF state**: 8 trait categories with controlled vocabularies in filter field tables. Filter guide (/filterguide) lists values without definitions or images. Glossary (/glossary) has 49 text-only definitions. The two pages don't connect to each other or to GallOnt. Implementation: lib/gallformers_web/live/filter_guide_live.ex.

## Trait mapping summary

Full mapping: docs/ontology/trait-mapping.md (generated 2026-02-14).

**Well-aligned**: Cells/chambers (monothalamous, polythalamous, free-rolling = near-exact). Detachable (GallOnt adds semideciduous). Plant parts (good PO coverage).

**Partially aligned**: Shape (5 direct of 13 GF values; GallOnt has ~15 GF lacks). Texture (7 matches of 24 GF values; GallOnt has ~15 GF lacks). Colors (basics align; GallOnt adds compound colors + patterns as separate axis). Forms (3 exact; most GF forms are practical field terms without ontology equivalents).

**GF-unique**: Alignment (orientation — not modeled in GallOnt at all). Seasons (GallOnt has no phenology; Prior Lab uses month-level granularity).

**GallOnt concepts GF lacks entirely**: Attachment style (sessile/pedicellate/semi-pedicellate), spatial pattern (solitary/clustered/confluent), quantitative size, internal tissue as separate category from walls, structural properties (fragility, opacity), specialized structures (emergence hole, kapello, abscission/dehiscence zones, nectaries), visibility (conspicuous/inconspicuous).

## Layered work plan

### Foundation (prerequisite for features)

**F1: Ontology IDs in the database** — Add optional ontology_id column to each filter field table (shapes, textures, walls, cells, colors, locations, alignments, forms). Populate from trait mapping for matched terms. No UI change. Makes the mapping machine-queryable and API-visible. Modest migration + seed script.

**F2: Illustrated term glossary** — Replace filter guide + glossary with unified reference page. Built from: GallOnt OBO (formal definitions + iNat seeAlso photo links), trait mapping (GF↔GallOnt correspondence), existing filter field tables. Design:
- Formal definitions from GallOnt (more precise than current text)
- Example photos from iNat (links already in OBO file)
- Deep-linkable anchors (/filterguide#monothalamous)
- Default view: GF terms only (serves current audience)
- Toggle view: full ontology vocabulary with GF terms highlighted (serves researchers)
- Visual indicator per term: maps to GF trait value vs GallOnt-only
- Cross-reference links to OLS viewer
- Does NOT depend on F1 — mapping can be static data or parsed from OBO at build time

Key insight: The glossary serves as curation reference (definitions + photos help volunteers score consistently), foundation for all downstream features, and researcher-facing interoperability layer — not just a nice-to-have.

### Features (builds on foundation)

**L1: Link traits to glossary entries** — Every trait value in the app (species pages, ID tool, admin) links to its glossary anchor. Instant access to definition + example photo. Depends on F2.

**L2: Trait hierarchy in ID tool** — Use ontology parent/child relationships to broaden filters. Selecting "hairy" implicitly matches subtypes (hispid, arachnose, felt-like). More forgiving for users who don't know precise terms. Depends on F1.

**L3: Prior Lab data ingest** — Shared ontology IDs let their scored datasets flow into GF as trait data. They score at species/generation level with photo evidence. Enriches records we lack volunteer capacity to curate. Depends on F1. Need to establish data format and update cadence with the lab.

### Exploratory (future possibilities, not yet scoped)

**E1: Ontology hierarchy browser** — Browse gall species through GallOnt hierarchy tree. Graph visualizations possible (Kirsten's Zoom demo). Depends on F1.

**E2: Trait gap analysis** — Curation tool: which GallOnt terms have no GF equivalent, which species are missing traits the ontology defines. Prioritizes data completeness work. Depends on F1.

**E3: Semantic similarity** — Ontology-grounded trait similarity between galls. Powers "similar galls" on species pages, flags potential misidentifications. Depends on F1.

## Decisions made

- GF will NOT change its user-facing trait vocabulary to match GallOnt. The mapping is behind the scenes. Everyday users see familiar GF terms; researchers see ontology context via toggle.
- The glossary (F2) is the highest-value, lowest-effort entry point and does not require DB changes.
- F1 (ontology IDs) is the gate for most feature and exploratory work.
- One parent matter (this one) spawns child matters per work item when execution begins.
