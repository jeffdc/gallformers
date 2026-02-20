---
status: raw
created: 2026-02-13
updated: 2026-02-19
epic: external
relates: [9737]
needs: [cc12]
---

# Data interoperability (DarwinCore, GBIF, Wikidata)

## DarwinCore

Gallformers is fundamentally a taxonomic checklist of gall-forming organisms and their host plants, enriched with morphological traits and geographic ranges. Natural fit is a GBIF Checklist dataset.

### Data Mapping

**Taxon (Core)**: Every species → Taxon row. Fields: taxonID (species.id), scientificName, kingdom (derived from taxoncode), family, genus, taxonRank, taxonomicStatus, vernacularName.

**ResourceRelationship**: Gall-host relationships — the core value no other database captures as comprehensively. Fields: resourceID (gall), relatedResourceID (host), relationshipOfResource (formsGallOn).

**MeasurementOrFact**: Gall traits (shape, color, texture, etc.). Each trait value = separate row.

**Distribution**: Geographic range at state/province/country level. host_range = present, gall_range_exclusion = absent.

**References**: Scientific literature backing the data.

### Integration Options (prioritized)

1. **DwC-A Export (Mix task)** — Foundation. ZIP containing meta.xml, eml.xml, taxon.txt, resourcerelationship.txt, measurementorfact.txt, distribution.txt, references.txt. Medium effort, high value.
2. **DwC-A download page** — Low effort on top of #1. Immediate user value.
3. **GBIF checklist registration** — Low effort on top of #1. Maximizes discoverability, gets DOI for citation.
4. **DwC-flavored API responses** — Nice-to-have, do later if demand.

## Catalogue of Life / ChecklistBank

Could publish gall-inducing species list as a thematic checklist on ChecklistBank. Format as ColDP (tabular text files). Overlaps significantly with DwC-A work.

## Wikidata

HIGH relevance. Integration path:
1. Propose a "Gallformers ID" property in Wikidata (like GBIF taxon ID = P846)
2. Add Gallformers links to taxon items via bot
3. Consume Wikidata QIDs as cross-references

Connects to Wikipedia, Google Knowledge Graph, broader linked data ecosystem.

## Bioschemas JSON-LD

Single most impactful low-effort addition. Add `<script type="application/ld+json">` block to each species page with Taxon markup. Improves SEO, makes data harvestable by aggregators.

## GNVerifier

Batch name verification against 100+ biodiversity databases. Validates species names, finds cross-references (GBIF IDs, COL IDs, ITIS TSNs), detects nomenclatural issues. Low effort, high value — enables everything else.

## Prioritized Roadmap

| Priority | Action | Effort | Impact |
|----------|--------|--------|--------|
| 1 | Bioschemas JSON-LD on species pages | Low | High |
| 2 | GNVerifier batch name matching | Low | High |
| 3 | DwC-A export (Mix task) | Medium | High |
| 4 | GBIF checklist registration | Low | High |
| 5 | Wikidata property proposal + linking | Medium | High |
| 6 | ChecklistBank / ColDP publication | Medium | Medium-High |
| 7 | Zenodo dataset archive with DOI | Low | Medium |
| 8 | DwC-A download page on site | Low | Medium |

## Open Questions

- License: CC0 (standard for GBIF) vs CC-BY?
- Scope: Include both gall species AND host plants?
- Update frequency: After every DB update? Weekly? On-demand?
- Identifiers: Raw numeric IDs vs prefixed URIs?
- Undescribed species: Include in archives?
- External ID mapping: Run GNVerifier first or publish without?


---

## Full Research Document

# Data Interoperability for Gallformers

This document surveys standards, platforms, and protocols relevant to making Gallformers data discoverable, citable, and interoperable with the broader biodiversity informatics ecosystem.

---

# Part 1: DarwinCore

## What is DarwinCore?

[Darwin Core (DwC)](https://dwc.tdwg.org/) is the standard vocabulary for sharing biodiversity data. It defines a set of terms (fields) for describing taxa, occurrences, locations, and relationships between organisms. It is the lingua franca of biodiversity informatics — used by GBIF, iNaturalist, VertNet, and thousands of other biodiversity databases worldwide.

## Why DarwinCore?

- **Discoverability**: Publishing to GBIF makes Gallformers data findable by researchers worldwide
- **Citability**: GBIF assigns DOIs to datasets, making Gallformers citable in scientific literature
- **Interoperability**: Other tools and databases can import/consume the data without custom integrations
- **Community alignment**: Positions Gallformers as a serious biodiversity resource, not just a website

## Gallformers as a DwC Dataset

Gallformers is fundamentally a **taxonomic checklist** of gall-forming organisms and their host plants, enriched with morphological traits and geographic ranges. It is **not** an occurrence dataset (we don't track individual observations with coordinates and dates — that's iNaturalist's domain).

GBIF supports several dataset types. The natural fit is:

- **Checklist** — A catalogue of taxa with names, classifications, and associated metadata
- Optionally enriched with extensions for relationships, traits, and distributions

## Data Mapping

### Taxon (Core)

The primary record type. Every species in Gallformers (both galls and hosts) becomes a Taxon row.

| DwC Term | Gallformers Source | Notes |
|---|---|---|
| `taxonID` | `species.id` | Stable numeric ID |
| `scientificName` | `species.name` | Full binomial |
| `kingdom` | Derived from `taxoncode` | "Animalia" for galls, "Plantae" for plants |
| `family` | `taxonomy` where `type="family"` | Via `species_taxonomy` join |
| `genus` | `taxonomy` where `type="genus"` | Via `species_taxonomy` join |
| `taxonRank` | Mostly `"species"` | Could derive from name structure |
| `taxonomicStatus` | `"accepted"` or `"undescribed"` | From `gall_traits.undescribed` |
| `acceptedNameUsage` | Primary `species.name` | When alias is a synonym |
| `vernacularName` | `alias.name` where `type="common"` | Via `alias_species` join |
| `taxonRemarks` | — | Could note undescribed status |

### ResourceRelationship (Extension)

The gall-host relationship — the core value of Gallformers that no other database captures as comprehensively.

| DwC Term | Gallformers Source | Notes |
|---|---|---|
| `resourceRelationshipID` | `gallhost.id` | Unique relationship ID |
| `resourceID` | `gallhost.gall_species_id` | The gall-forming organism |
| `relatedResourceID` | `gallhost.host_species_id` | The host plant |
| `relationshipOfResource` | `"formsGallOn"` | Or DwC's `"parasiteOf"` |
| `relationshipAccordingTo` | Source citation | If we track which source documents the association |

### MeasurementOrFact (Extension)

Gall traits (morphological characteristics used for identification). Each trait value becomes a separate row.

| DwC Term | Gallformers Source | Notes |
|---|---|---|
| `measurementID` | Generated | Composite of species_id + trait type + value |
| `measurementType` | Trait category | `"shape"`, `"color"`, `"texture"`, `"alignment"`, `"walls"`, `"cells"`, `"form"`, `"season"`, `"plantPart"`, `"detachable"` |
| `measurementValue` | Trait value | e.g., `"spherical"`, `"red"`, `"hairy"` |
| `measurementRemarks` | Trait description | From the filter field `description` column |

A single gall with 3 colors and 2 shapes would produce 5 MeasurementOrFact rows.

### Distribution (Extension)

Geographic range data. Gallformers tracks ranges at the state/province/country level, not coordinates.

| DwC Term | Gallformers Source | Notes |
|---|---|---|
| `locationID` | `place.id` | |
| `locality` | `place.name` | e.g., "California", "Ontario" |
| `countryCode` | `place.code` | For country-level places |
| `occurrenceStatus` | `"present"` or `"absent"` | `host_range` = present, `gall_range_exclusion` = absent |

### References (Extension)

Scientific literature backing the data.

| DwC Term | Gallformers Source | Notes |
|---|---|---|
| `identifier` | `source.link` | URL to the publication |
| `bibliographicCitation` | `source.citation` | Full citation text |
| `title` | `source.title` | |
| `creator` | `source.author` | |
| `date` | `source.pubyear` | Publication year |

## What Gallformers Lacks for Full DwC

These are **not blockers** for a checklist — they're relevant only for occurrence datasets:

- **Individual observations** — No `basisOfRecord`, `catalogNumber`, `recordedBy`
- **Precise coordinates** — Places are regions (states, provinces), not lat/long points
- **Temporal data** — No observation dates for individual specimens
- **Collection/specimen data** — No museum voucher references

This is expected. Gallformers is a reference database, not a specimen catalog.

## Integration Options

### Option 1: DwC-A Export (Darwin Core Archive)

**What**: A Mix task that generates a Darwin Core Archive — a ZIP file containing:
- `meta.xml` — Describes the CSV schema and extensions
- `eml.xml` — Dataset metadata (title, description, contacts, license)
- `taxon.txt` — Core taxon records (all species)
- `resourcerelationship.txt` — Gall-host associations
- `measurementorfact.txt` — Gall traits
- `distribution.txt` — Geographic ranges
- `references.txt` — Scientific literature

**Effort**: Medium. Read-only queries against existing data, format into CSVs, package.

**Value**: High. This is the standard interchange format. Can be:
- Hosted as a static download on the site
- Registered with GBIF for periodic crawling
- Consumed by any DwC-compatible tool

**Implementation sketch**:
```
mix gallformers.dwc_archive [--output path/to/output.zip]
```

Could also be triggered on a schedule (e.g., weekly cron or after DB updates) and uploaded to S3 for download.

### Option 2: DwC-Flavored API Responses

**What**: Add a `?format=dwc` parameter to existing API endpoints that returns JSON-LD using DwC term IRIs as keys.

**Example**:
```json
{
  "@context": "https://dwc.tdwg.org/terms/",
  "taxonID": "1234",
  "scientificName": "Andricus quercuscalifornicus",
  "family": "Cynipidae",
  "genus": "Andricus"
}
```

**Effort**: Low-medium. Mostly a serialization layer on existing API responses.

**Value**: Moderate. Useful for programmatic consumers who want DwC field names, but doesn't integrate with the GBIF ecosystem (which expects DwC-A files, not APIs).

### Option 3: GBIF IPT Registration

**What**: Register Gallformers as a dataset with GBIF's [Integrated Publishing Toolkit](https://www.gbif.org/ipt). GBIF crawls a DwC-A endpoint periodically and indexes the data.

**Effort**: Low (on top of Option 1). Requires:
- Hosting the DwC-A file at a stable URL
- Registering with GBIF (free, requires an institutional account)
- Providing an `eml.xml` with dataset metadata and contact info

**Value**: Very high. Gallformers data becomes searchable on gbif.org, gets a DOI for citation, and appears in global biodiversity analyses.

**Prerequisite**: Option 1 (the archive must exist to register it).

### Option 4: DwC-A Download Page

**What**: Add a `/downloads` or `/data` page to the site where users can download the DwC-A file directly, alongside the existing database download.

**Effort**: Low (on top of Option 1). A page with a download link and documentation about the archive contents.

**Value**: Moderate. Makes the data accessible to researchers who want DwC format but aren't going through GBIF.

## Recommended Path

These options are not mutually exclusive — they build on each other:

1. **Start with Option 1** (DwC-A export) — This is the foundation everything else depends on
2. **Add Option 4** (download page) — Low effort, immediate user value
3. **Register with GBIF (Option 3)** — Maximizes discoverability and citable impact
4. **Option 2** (API format) — Nice-to-have, do later if there's demand

The DwC-A export is a contained piece of work: a Mix task that reads the DB and writes a ZIP file. No schema changes, no new dependencies beyond CSV/ZIP generation (both in Erlang stdlib). The mapping is straightforward because the Gallformers data model already has clean separations between taxa, relationships, traits, and locations.

## Open Questions

- **License**: What license for the DwC-A dataset? CC0 is standard for GBIF, but CC-BY is also accepted. Gallformers sources have individual licenses — the checklist data itself could be CC0 while linking to sources with their own licenses.
- **Scope**: Include both gall species AND host plants in the taxon core, or just gall species? Including hosts makes the ResourceRelationship extension self-contained.
- **Update frequency**: How often to regenerate the archive? After every DB update? Weekly? On-demand?
- **Identifiers**: Should `taxonID` be the raw numeric ID or a prefixed URI like `https://gallformers.org/species/1234`?
- **Undescribed species**: Include them in the archive? GBIF supports `taxonomicStatus: "undescribed"` but some publishers omit them.

---

# Part 2: AT Protocol

## What is AT Protocol?

[AT Protocol](https://atproto.com/) is the decentralized protocol behind Bluesky. Its core strengths are decentralized identity (DIDs), federated data repositories, custom schemas (Lexicons), and algorithmic choice. It was designed for social applications with many participants publishing data that many consumers want to remix and filter.

## Relevance to Gallformers: Low

AT Protocol solves problems Gallformers doesn't have:

- **Decentralized identity** — Gallformers has a small editorial team, not a crowd of users needing portable identities
- **Federation** — There's one canonical source of gall taxonomy; federation adds complexity without value
- **Algorithmic choice** — Not relevant for a reference database
- **Real-time firehose** — Data changes slowly (new species, updated traits)

The fundamental mismatch: AT Protocol is designed for **many participants publishing data that many consumers remix**. Gallformers is **one authoritative source publishing structured data that consumers query**.

## What Could Work

**Bluesky bot**: Post new species additions, interesting galls, or seasonal highlights to Bluesky. Practically useful for community engagement, but this is "use the Bluesky API" not an AT Protocol integration. Low effort, modest value.

**ATproto Science**: An [early-stage initiative](https://atproto.science/) building research infrastructure on AT Protocol, with a conference planned for March 2026 in Vancouver. If they gain traction building tools for scientific data curation and discussion, there might be a future fit. Speculative for now.

## Verdict

Not recommended as a priority. The biodiversity informatics ecosystem has mature, purpose-built standards (DarwinCore, GBIF, Catalogue of Life) that directly address Gallformers' interoperability needs. AT Protocol may become relevant if ATproto Science matures, but the ROI today is near zero.

---

# Part 3: Biodiversity Platforms and Registries

## Catalogue of Life (COL) / ChecklistBank

[Catalogue of Life](https://www.catalogueoflife.org/) aims to be the definitive list of all known species. [ChecklistBank](https://www.checklistbank.org/) is its open repository where anyone can publish taxonomic checklists. COL's infrastructure is now hosted jointly with GBIF.

**Relevance**: HIGH. Gallformers could publish its gall-inducing species list as a thematic checklist on ChecklistBank, potentially becoming a recognized sector of COL for gall-forming organisms.

**Integration**:
- Format data as **ColDP** (Catalogue of Life Data Package) — tabular text files: `NameUsage.tsv`, `Synonym.tsv`, `VernacularName.tsv`, `Distribution.tsv`, `Reference.tsv`
- Alternative: DarwinCore Archive format (also accepted)
- Upload directly to ChecklistBank or host at a stable URL
- Published checklists receive DOIs

**Adoption**: COL includes 2.15M+ accepted species. ChecklistBank underpins both COL and GBIF's taxonomic backbone.

**Effort**: Medium — largely overlaps with the DwC-A export work. ColDP is a slightly different tabular format but maps to the same data.

## Encyclopedia of Life (EOL)

[EOL](https://eol.org/) aggregates species information from content partners into rich species pages. Its TraitBank stores organism traits, measurements, and interactions.

**Relevance**: MEDIUM. EOL's TraitBank could host gall morphological traits (shape, color, texture, detachability). However, EOL has been less active in recent years compared to GBIF/COL. Content is contributed by institutional "content partners" — not self-service.

**Integration**: Become an EOL content partner (institutional process). Data is matched to EOL pages by scientific name.

**Effort**: High (institutional process). **Value**: Low-medium given platform trajectory.

## iNaturalist

[iNaturalist](https://www.inaturalist.org/) is the largest citizen science biodiversity platform (170M+ observations, 400K+ species). It's primarily an observation platform, not a reference database.

**Relevance**: LOW for data contribution (iNat doesn't accept curated reference data), MEDIUM for linking and consuming.

**Integration options**:
- **Be linked as an external resource** — iNaturalist curators can add Gallformers as a "More Info" link on gall-forming species taxon pages
- **Consume iNat data** — Research Grade observations flow to GBIF; Gallformers could pull occurrence data for gall-forming species to enrich range maps
- **Taxonomic authority** — Publishing a GBIF checklist feeds into the backbone that iNaturalist references

**Key insight**: The relationship with citizen science platforms is as a **taxonomic authority they reference** and a **consumer of their observation data**, not as a data contributor.

## ITIS (Integrated Taxonomic Information System)

[ITIS](https://www.itis.gov/) is a partnership of US, Canadian, and Mexican agencies maintaining taxonomic information. Part of the Catalogue of Life.

**Relevance**: LOW for contribution (formal process with taxonomic specialists). Useful as a reference for validating names and obtaining TSN identifiers.

## Wikidata / Wikispecies

[Wikidata](https://www.wikidata.org/) is the structured data backend for all Wikimedia projects, with extensive taxonomic coverage via [WikiProject Taxonomy](https://www.wikidata.org/wiki/Wikidata:WikiProject_Taxonomy).

**Relevance**: HIGH. Wikidata is the linchpin of the linked open data web for biodiversity.

**Integration path**:
1. **Propose a "Gallformers ID" property** in Wikidata — An external identifier property that lets any Wikidata taxon item link directly to its gallformers.org page. Many biodiversity databases have their own properties (GBIF taxon ID = P846, BugGuide ID, iNaturalist taxon ID, etc.). Requires a [Property Proposal](https://www.wikidata.org/wiki/Wikidata:Property_proposal/Authority_control) and community consensus.
2. **Add Gallformers links to taxon items** — Using a bot or manually, add the Gallformers species ID to each Wikidata item for gall-inducing species.
3. **Consume Wikidata** — Use Wikidata QIDs as cross-references in Gallformers, linking to the broader knowledge graph.

**Effort**: Medium (proposal process + bot development). **Value**: High — connects Gallformers to Wikipedia, Google Knowledge Graph, and the broader linked data ecosystem.

---

# Part 4: Linked Data and Semantic Web

## Bioschemas Taxon Profile (JSON-LD)

[Bioschemas](https://bioschemas.org/) extends schema.org with profiles for life sciences, including a [Taxon 1.0-RELEASE](https://bioschemas.org/profiles/Taxon/1.0-RELEASE) profile. This is structured data markup embedded in HTML pages.

**Relevance**: HIGH. This is the single most impactful low-effort thing Gallformers could add. Google and other search engines consume JSON-LD markup. Adding Bioschemas Taxon markup to species pages would:
- Improve search engine results for species pages
- Make Gallformers data harvestable by biodiversity aggregators
- Link Gallformers taxa to GBIF, Wikidata, COL via `identifier` and `sameAs` properties

**Implementation**: Add a `<script type="application/ld+json">` block to each species page template:

```json
{
  "@context": "https://schema.org/",
  "@type": "Taxon",
  "name": "Andricus quercuscalifornicus",
  "taxonRank": "species",
  "parentTaxon": {
    "@type": "Taxon",
    "name": "Andricus",
    "taxonRank": "genus"
  },
  "identifier": [
    {
      "@type": "PropertyValue",
      "name": "Gallformers ID",
      "value": "123"
    }
  ],
  "sameAs": ["https://www.wikidata.org/entity/Q12345"],
  "url": "https://gallformers.org/species/123"
}
```

**Effort**: Low — a template change in the species detail LiveView. **Value**: High — SEO + machine readability.

**Adoption**: Deployed at the National Museum of Natural History (Paris), Meise Botanic Garden, and growing.

## OpenBiodiv Knowledge Graph

A linked open data knowledge graph extracting structured biodiversity data from scientific literature. Uses RDF/SPARQL. Integrates data from Pensoft journals and Plazi's TreatmentBank.

**Relevance**: LOW for direct integration. Could be a downstream consumer of Gallformers data if published as linked data. Its SPARQL endpoint could be useful for querying literature references about gall-forming species.

---

# Part 5: Taxonomic Name Services

## Global Names Verifier (GNVerifier)

[GNVerifier](https://verifier.globalnames.org/) is a fast name verification service that matches scientific names against 100+ biodiversity databases simultaneously. Supports exact, fuzzy, and partial matching.

**Relevance**: HIGH for data quality and cross-referencing. Gallformers could use GNVerifier to:
- Validate all species names against authoritative sources
- Find cross-references (GBIF IDs, COL IDs, ITIS TSNs) for each species
- Detect nomenclatural issues (misspellings, outdated synonyms)
- Build a mapping table from Gallformers species to external identifiers

**Integration**: REST API or local Go binary (`gnverifier`). POST a batch of names, get back matched names with source database IDs.

**Effort**: Low (a one-time batch API call to build the mapping table). **Value**: High — enables everything else (GBIF registration, Wikidata linking, Bioschemas `sameAs`).

## GBIF Species API

GBIF's [species name matching API](https://techdocs.gbif.org/en/openapi/v1/species). Fuzzy-matches names, looks up taxonomic trees, retrieves cross-references. Also offers a [Species Lookup tool](https://www.gbif.org/tools/species-lookup) for CSV batch matching.

**Relevance**: HIGH. Complementary to GNVerifier. Can provide GBIF taxon keys for each Gallformers species.

## Taxonomic Name Resolution Service (TNRS)

[TNRS](https://tnrs.biendata.org/) — focused specifically on plant names. Accepts up to 5,000 names for resolution against multiple plant taxonomic databases.

**Relevance**: MEDIUM. Useful specifically for validating host plant names. Less useful for gall-forming insects/mites.

---

# Part 6: Scientific Data Standards

## FAIR Principles

**F**indable, **A**ccessible, **I**nteroperable, **R**eusable — the de facto framework for scientific data stewardship. Not a technical standard but a set of principles:

- **Findable**: Persistent identifiers (DOIs), rich metadata, registered in searchable resources
- **Accessible**: Open protocols (HTTPS), clear licensing
- **Interoperable**: Community standards (DarwinCore, ColDP, Bioschemas)
- **Reusable**: Clear provenance, domain-relevant attributes

Most items in this document are the concrete implementations that make data FAIR. Publishing to GBIF, adding Bioschemas markup, and getting a DOI collectively satisfy these principles.

## Zenodo + DOI via DataCite

[Zenodo](https://zenodo.org/) is a general-purpose open repository hosted by CERN. It assigns DataCite DOIs to uploaded datasets, making them permanently citable. Free, no institutional affiliation required.

**Relevance**: MEDIUM-HIGH. Gallformers could publish periodic database snapshots to Zenodo:
- Each upload gets a DOI; versions are linked
- One "concept DOI" always resolves to the latest version
- Max 50GB per dataset
- Can be automated via REST API

This is complementary to GBIF/COL (which provide live integration) — Zenodo provides a **permanent, versioned, citable archive**.

**Effort**: Low (upload a snapshot). **Value**: Medium (citability in scientific papers).

## Ecological Metadata Language (EML)

XML metadata standard for ecological datasets. Used by GBIF as its metadata format. If publishing to GBIF via IPT, you write EML as part of the process (the IPT has a form editor for it). Not something to implement independently.

---

# Part 7: Emerging Initiatives

## Plazi TreatmentBank

[Plazi](https://plazi.org/) extracts structured taxonomic treatments from scientific literature PDFs. Each treatment gets a DataCite DOI. 284,000+ treatments extracted. If Gallformers cites scientific literature for species descriptions, TreatmentBank may already have structured extractions of those papers.

**Relevance**: MEDIUM as a data source for enriching literature references.

## TDWG 2026: "Research and Robot-ready Biodiversity Data Standards"

The upcoming [TDWG](https://www.tdwg.org/) conference in Oslo (September 2026) focuses on making biodiversity data machine-readable. Signals community direction: standards will increasingly support automated consumption. Confirms that investing in machine-readable formats aligns with where the community is heading.

## ATproto Science

[Early-stage initiative](https://atproto.science/) building research infrastructure on AT Protocol. Conference planned for March 2026 in Vancouver. Worth monitoring but not actionable now.

---

# Part 8: Data Flow in the Ecosystem

Understanding how data flows between different types of biodiversity platforms:

```
Citizen Science (iNaturalist, BugGuide)
  │
  │ Research-grade observations
  ▼
GBIF (aggregator) ◄──── Curated Databases (Gallformers, COL, WoRMS)
  │                       │
  │                       │ Checklist datasets, taxonomic backbones
  ▼                       ▼
Researchers         Wikidata / Wikipedia
  │                       │
  │                       ▼
  └──────────────► Scientific Literature
```

**Gallformers' role**: A **taxonomic authority** for gall-forming organisms that feeds into GBIF/COL, is referenced by citizen science platforms, and links to Wikidata. It **consumes** observation data from iNaturalist (via GBIF) to enrich range information.

---

# Prioritized Roadmap

Based on effort-to-impact ratio for a curated reference database:

| Priority | Action | Effort | Impact | Dependencies |
|----------|--------|--------|--------|-------------|
| 1 | **Bioschemas JSON-LD on species pages** | Low | High | None |
| 2 | **GNVerifier batch name matching** | Low | High | None |
| 3 | **DwC-A export (Mix task)** | Medium | High | None |
| 4 | **GBIF checklist registration** | Low | High | #3 |
| 5 | **Wikidata property proposal + linking** | Medium | High | #2 |
| 6 | **ChecklistBank / ColDP publication** | Medium | Medium-High | #3 (overlapping work) |
| 7 | **Zenodo dataset archive with DOI** | Low | Medium | None |
| 8 | **DwC-A download page on site** | Low | Medium | #3 |
| 9 | **iNaturalist observation consumption** | Medium | Medium | GBIF API access |
| 10 | **DwC-flavored API responses** | Low-Medium | Low-Medium | Nice-to-have |

Items 1-2 are quick wins that enable everything else. Item 3 is the foundational export that unlocks GBIF, COL, and downloads. Items 4-6 maximize discoverability. The rest are incremental.

---

# Open Questions

- **License**: CC0 is standard for GBIF checklist data. CC-BY is also accepted. The checklist data itself could be CC0 while individual sources retain their own licenses.
- **Scope**: Include both gall species AND host plants in exports? Including hosts makes the ResourceRelationship data self-contained.
- **Update frequency**: Regenerate archives after every DB update? Weekly? On-demand?
- **Identifiers**: Raw numeric IDs vs. prefixed URIs (`https://gallformers.org/species/1234`)?
- **Undescribed species**: Include in archives? GBIF supports `taxonomicStatus: "undescribed"`.
- **External ID mapping**: Run GNVerifier first to build a cross-reference table, or start publishing without external IDs?
