---
status: raw
created: 2026-10-02
updated: 2026-10-04
epic: taxonomy
relates: [1121, 8567]
---

# Taxonomy migration

How to move today's data and application onto the domain model ([`docs/domain/domain-model.md`](../../docs/domain/domain-model.md)) and the owned-taxonomy design in matter `8567`. This matter tracks the migration details.

## Phases

- **Phase 1 (gall system):** split galls from species — gall entries keep their IDs; inducer taxa are created from the gall rows, merging generation pairs — and add the taxon identity layer over today's taxonomy tables.
- **Phase 2 (taxonomy system):** move taxa into the rebuilt taxonomy system behind the same taxon IDs; plants become POWO-imported taxa.

## Work items

- **Inducer taxa** from gall rows: ~2,440 distinct described names, merging the 76 agamic/sexgen pairs; undescribed galls link at genus or section (625) or at the family named in a placeholder genus (927).
- **Taxon identity layer:** one stable taxon ID for every existing `species` row and `taxonomy` node.
- **iNat correspondence (optional):** iNat taxon IDs as external references, useful for observations and barcodes, not for taxonomy. Name matching works well (see *iNat correspondence*).
- **Non-gall review**: hand-review all 120 `form = non-gall` records; don't migrate them; redirect their URLs to a new gall-lookalikes Article (write the Article).
- **Name-suffix mapping**: ~900 tokens map mechanically to the generation trait; curate the 47 names listed under *Name-suffix categorization*.
- **Alias classification**: gall "scientific" aliases → taxon synonymy; gall common names → gall facts.
- **Placeholder genera**: map each "Unknown (Family)" placeholder's galls to a family-level inducer link (or none).
- **Taxonomy ID crosswalk** for the legacy `/taxonomy/:id` redirect.
- **Key couplets**: review each of the 4 keys' targets (gall or taxon).
- **iNat observation IDs**: parse the 5,365 iNat image URLs.
- **Rerun the inventory** before final planning; last run 2026-10-02 against a production copy.

## Migration notes

- **Order: build the pipeline, migrate, backscan, then release.** Legacy data is migrated as-is so the new system runs, the backscan attributes it, and only then is it released.
- **IDs.** Today galls and plants share the `species` ID sequence; higher taxa have a separate `taxonomy` ID sequence. After the split:
  - Galls keep their species IDs, so `/gall/:id` and the API's `/galls/:id` stay valid.
  - Plant taxa keep their species IDs, so `/host/:id` stays valid.
  - Inducer taxa get new IDs: one inducer can merge several old rows (e.g. its agamic and sexgen galls), and the gall keeps the old number.
  - Higher taxa get new IDs; 1,562 of their 1,615 old IDs collide with species IDs. Only the legacy `/taxonomy/:id` redirect needs a crosswalk — genus and family pages are addressed by name.
  - Each system owns its own IDs; cross-system references are typed. New taxa draw from the taxonomy system's sequence, starting above today's highest species ID (7,143 in the 2026-09-30 production copy) so they don't clash with the plant IDs it keeps.
- **Genus placeholder plants** ("*Quercus* spp.") become genus-level host links, and **their range data keeps contributing to the theoretical range exactly as today.** The code check that said placeholders have no range data was wrong: 86 of the 159 placeholders own 89,328 host-range rows (e.g. *Bidens* spp. 4,100, *Hibiscus* spp. 4,018), and today's host-union fallback includes them. Dropping them would narrow ID results.
- **Placeholder genera** ("Unknown (Cynipidae)", 102 of them) are not migrated. Galls linked to them get an inducer link at the family named in the placeholder, or no inducer link for "Unknown (Unknown)".
- **Name suffixes need a curated mapping, not a parser.** Parentheses in gall names carry generation terms (agamic, sexgen, spring/summer generation), rust spore stages (aecial, telial), and host-scoped forms ("on betula", "(q-bicolor)", even "(agamic) (q-bicolor)").
- **Aliases.** "Scientific" aliases on gall rows are mostly inducer synonyms and move to the taxon side. Common names on galls become gall facts; none has a Source today.
- **Non-galls are reviewed by hand, then not migrated.** All 120 `form = non-gall` records get a manual review. They don't enter the new model; their old URLs redirect to a new Article about gall lookalikes.
- **Today's stored gall range** becomes range Facts only once backed by Sources (the backscan). Only 44 of 3,509 galls with a stored range are marked confirmed; most stored ranges are probably copies of host unions. Observational data (Research Grade iNat overlay) is a separate, future layer.
- **The ID tool changes from "stored range, else host union" to the theoretical range.** That may broaden some results; verify it doesn't make ID worse.
- **Images from iNat** (5,365 of 7,663 gall images) store the observation URL; parsing it recovers observation IDs and gives a head start on observation links.
- **Keys** (4) have couplets pointing at species IDs; each target needs a semantic review (gall or taxon).
- **Plants become POWO-imported taxa** (phase 2), keeping their WCVP/POWO IDs; curators can adjust them editorially. Host distributions stay outside Facts.

## iNat correspondence (research 2026-10-02)

Researched when the plan was to mirror iNat; under the owned-taxonomy direction this is optional correspondence, not taxonomy.

Read-only research: 156 unauthenticated requests to the iNat API, plus iNat's source code on GitHub. Raw data (samples, per-name results, API responses, inventory queries, curation list): `docs/plans/2026-10-02-taxonomy-migration-research/` (local, gitignored).

**Name-matching test** (random sample from the production copy):

| | Exact match, active | Synonym (auto-resolves) | Not in iNat |
|---|---|---|---|
| Plants (60) | 58 (97%) | 1 | 1 (*Salix groenlandica*) |
| Inducers (64) | 55 (86%) | 1 | 8 |

- **Projection:** ~2,500 plants match automatically (~80 to curate); ~2,100 inducers match automatically (~300–350 to curate). The inducer sample is small; treat its rate as ±10 points.
- **Missing inducers are genuinely absent from iNat**, not misspelled — mostly little-known cynipids (e.g. *Andricus santafe*, *Neuroterus fusifex*, *Diplolepis tuberculosa*). They simply have no iNat correspondence.
- **Matching method:** `GET /v1/taxa?q=<name>&is_active=any`, then exact name match, filter by kingdom, keep only active taxa, prefer species rank. Same-name inactive duplicates are common; a few names collide across ranks (e.g. *Ulmus minor* complex vs species).
- **Synonyms resolve automatically:** an inactive taxon points to its successor via `current_synonymous_taxon_ids` (e.g. *Hieracium flagellare* → *Pilosella flagellaris*).
- **No POWO route for plants.** iNat follows POWO for vascular plants but exposes no POWO/WCVP IDs (v1 has no such field; framework endpoints error or are blocked). Match on the POWO-accepted name instead.
- **Infraspecific names:** iNat has no pathovar rank; *Pseudomonas savastanoi* (pv. *nerii*) matches only at species. Phytoplasmas lack the "Candidatus" prefix.

**Caching:** our ~5,000 taxa plus ancestors (likely <10,000) fit in ~25–50 batched calls (`/v1/taxa?id=…`, up to at least 115 IDs per call; `per_page` max 500). Every record carries `ancestor_ids`. iNat also publishes a monthly taxonomy export (`inaturalist-taxonomy.dwca.zip`, ~81 MB): active taxa only, no synonyms, no authorship — usable for an initial seed or cross-check.

## Name-suffix categorization (2026-10-02)

Parentheses in gall names (excluding the "Unknown (Family)" placeholder prefix) hold 46 distinct tokens across 948 occurrences. They encode four dimensions the new model separates: **generation, host, form, and name history**. Some names stack three, e.g. *Neuroterus quercicola* (pacificus) (sexgen) (on Quercus douglasii).

| Category | Tokens | Count | Target in the new model |
|---|---|---|---|
| Cynipid generation | agamic, sexgen | 877 | Generation trait. Mechanical mapping. |
| Seasonal generation | spring / summer / autumn / "summer and autumn" generation(s) | 22 | Generation trait with group-specific terms. "Summer and autumn generations" is one entry covering two generations. |
| Rust spore stage | telial, aecial | 4 | Life-cycle stage; recommended: generation trait. Each stage is on a different host. |
| Host-scoped | "on Betula", "on Malus", "on Quercus lobata", "q-bicolor", … | 20 | Host relationships plus a host qualifier in the name. Two different situations; see below. |
| Plant part / form | bud, leaf snap, capitulum, inflorescence, detachable bud, integral stem, leaf, midrib gall, deforming-pisiformis | 13 | Separate entries for one species (boundary case 4): plant-part/form trait plus a form qualifier in the name. |
| Historical / infraspecific name | pacificus, texanus, australis, cerinus, decrescens, rydbergiana, saltatorius, perforans | 10 | Gall alias (former name). Some may be cryptic species; curator review. |
| Pathovar | pv nerii | 1 | Part of the taxon name (an infraspecific rank in Gallformers' taxonomy). |
| Relationship | altering Diplolepis gall | 1 | *Modified form of* relationship. |

**Findings**

- **~900 of the 948 tokens map mechanically** (cynipid and seasonal generation terms). **47 gall names need a curator**; they're listed below.
- **"On X" covers two biological situations.** Host-alternating life cycles (aphids: *Hamamelistes*, *Hormaphis*, *Eriosoma*, *Prociphilus*; heteroecious rusts: *Gymnosporangium*) are different life-cycle phases on alternate hosts, so they belong in the generation trait under a group-specific vocabulary. The same phase on different hosts (eriophyids, *Contarinia*, *Neuroterus* sexgen on *Q. douglasii* vs *Q. lobata*) is a separate entry distinguished by host. **Recommended: treat host-alternating phases as generation — awaiting Jeff's confirmation.**
- **The name builder needs qualifiers** (requirement for `86e7`). Names are unique, and one inducer + generation can have several entries, so a derived name adds a generation, then a host, then a form qualifier as needed.

**Curation list** (production copy, 2026-10-02). Handling is a proposal; each row needs a curator decision.

| ID | Gall name | Category | Proposed handling |
|---|---|---|---|
| 3396 | Cynips mellea (rydbergiana) (agamic) | Historical / infraspecific name | parenthetical name → gall alias (former name); curator checks for a cryptic species |
| 2128 | Neuroterus quercicola (pacificus) (agamic) | Historical / infraspecific name | parenthetical name → gall alias (former name); curator checks for a cryptic species |
| 3167 | Neuroterus quercicola (pacificus) (sexgen) (on Quercus douglasii) | Historical / infraspecific name, Host-scoped | parenthetical name → gall alias (former name); curator checks for a cryptic species; same phase, different host → separate entry; host relationship + host qualifier in name |
| 1996 | Neuroterus quercicola (pacificus) (sexgen) (on Quercus lobata) | Historical / infraspecific name, Host-scoped | parenthetical name → gall alias (former name); curator checks for a cryptic species; same phase, different host → separate entry; host relationship + host qualifier in name |
| 1720 | Neuroterus saltatorius (agamic) (saltatorius) | Historical / infraspecific name | parenthetical name → gall alias (former name); curator checks for a cryptic species |
| 1076 | Neuroterus saltatorius (australis) (agamic) | Historical / infraspecific name | parenthetical name → gall alias (former name); curator checks for a cryptic species |
| 2450 | Neuroterus saltatorius (decrescens) (agamic) | Historical / infraspecific name | parenthetical name → gall alias (former name); curator checks for a cryptic species |
| 1109 | Neuroterus saltatorius (texanus) (agamic) | Historical / infraspecific name | parenthetical name → gall alias (former name); curator checks for a cryptic species |
| 3168 | Neuroterus vesicula (cerinus) (sexgen) | Historical / infraspecific name | parenthetical name → gall alias (former name); curator checks for a cryptic species |
| 2915 | Phylloxera caryaesepta (perforans) | Historical / infraspecific name | parenthetical name → gall alias (former name); curator checks for a cryptic species |
| 6860 | Colomerus tricaseri (on Empogona kirkii) | Host-scoped | same phase, different host → separate entry; host relationship + host qualifier in name |
| 6862 | Colomerus tricaseri (on Sericanthe andongensis) | Host-scoped | same phase, different host → separate entry; host relationship + host qualifier in name |
| 2338 | Contarinia partheniicola (on Ambrosia) | Host-scoped | same phase, different host → separate entry; host relationship + host qualifier in name |
| 5512 | Contarinia partheniicola (on Parthenium incanum) | Host-scoped | same phase, different host → separate entry; host relationship + host qualifier in name |
| 3248 | Eriophyes cerasicrumena (on Prunus americana) | Host-scoped | same phase, different host → separate entry; host relationship + host qualifier in name |
| 633 | Eriophyes cerasicrumena (on Prunus serotina) | Host-scoped | same phase, different host → separate entry; host relationship + host qualifier in name |
| 2688 | Eriosoma lanigerum (on Malus) | Host-scoped | life-cycle phase on an alternate host → generation trait (recommended); host relationship |
| 4089 | Eriosoma lanigerum (on Ulmus) | Host-scoped | life-cycle phase on an alternate host → generation trait (recommended); host relationship |
| 5578 | Gymnosporangium nidus-avis (on Juniper) | Host-scoped | life-cycle phase on an alternate host → generation trait (recommended); host relationship |
| 2960 | Gymnosporangium sabinae (on Pyrus) | Host-scoped | life-cycle phase on an alternate host → generation trait (recommended); host relationship |
| 2255 | Hamamelistes spinosus (on Betula) | Host-scoped | life-cycle phase on an alternate host → generation trait (recommended); host relationship |
| 1005 | Hamamelistes spinosus (on Hamamelis) | Host-scoped | life-cycle phase on an alternate host → generation trait (recommended); host relationship |
| 3981 | Hormaphis cornu (on Betula) | Host-scoped | life-cycle phase on an alternate host → generation trait (recommended); host relationship |
| 3979 | Hormaphis cornu (on Hamamelis) | Host-scoped | life-cycle phase on an alternate host → generation trait (recommended); host relationship |
| 1340 | Neuroterus quercusbatatus (agamic) (q-bicolor) | Host-scoped | same phase, different host → separate entry; host relationship + host qualifier in name |
| 1339 | Neuroterus quercusbatatus (sexgen) (on Quercus bicolor) | Host-scoped | same phase, different host → separate entry; host relationship + host qualifier in name |
| 5095 | Phytoplasma pruni (on Trillium) | Host-scoped | same phase, different host → separate entry; host relationship + host qualifier in name |
| 4092 | Prociphilus caryae (on Amelanchier) | Host-scoped | life-cycle phase on an alternate host → generation trait (recommended); host relationship |
| 5120 | Pseudomonas savastanoi (pv nerii) | Pathovar | pathovar is part of the taxon name → infraspecific taxon in Gallformers' taxonomy |
| 6613 | Acalitus pundamariae (inflorescence) | Plant part / form | separate entry for one species → plant-part/form trait + form qualifier in name |
| 6612 | Acalitus pundamariae (leaf) | Plant part / form | separate entry for one species → plant-part/form trait + form qualifier in name |
| 4931 | Andricus notholithocarpi (midrib gall) | Plant part / form | separate entry for one species → plant-part/form trait + form qualifier in name |
| 2841 | Asphondylia pseudorosa (bud) | Plant part / form | separate entry for one species → plant-part/form trait + form qualifier in name |
| 2887 | Asphondylia pseudorosa (capitulum) | Plant part / form | separate entry for one species → plant-part/form trait + form qualifier in name |
| 2886 | Asphondylia pseudorosa (leaf snap) | Plant part / form | separate entry for one species → plant-part/form trait + form qualifier in name |
| 2892 | Asphondylia rosulata (bud) | Plant part / form | separate entry for one species → plant-part/form trait + form qualifier in name |
| 2891 | Asphondylia rosulata (leaf snap) | Plant part / form | separate entry for one species → plant-part/form trait + form qualifier in name |
| 2889 | Asphondylia solidaginis (bud) | Plant part / form | separate entry for one species → plant-part/form trait + form qualifier in name |
| 2888 | Asphondylia solidaginis (leaf snap) | Plant part / form | separate entry for one species → plant-part/form trait + form qualifier in name |
| 3235 | Tanaostigmodes howardii (detachable bud) | Plant part / form | separate entry for one species → plant-part/form trait + form qualifier in name |
| 2047 | Tanaostigmodes howardii (integral stem) | Plant part / form | separate entry for one species → plant-part/form trait + form qualifier in name |
| 1519 | Unknown (Cynipidae) q-alba-(deforming-pisiformis) | Plant part / form | separate entry for one species → plant-part/form trait + form qualifier in name |
| 2419 | Periclistus pirata (altering Diplolepis gall) | Relationship | inquiline-modified gall → *modified form of* relationship to the Diplolepis gall |
| 1247 | Cronartium quercuum (telial) | Rust spore stage | rust life-cycle stage → generation trait (recommended) |
| 6002 | Gymnosporangium floriforme (aecial) | Rust spore stage | rust life-cycle stage → generation trait (recommended) |
| 6460 | Gymnosporangium floriforme (telial) | Rust spore stage | rust life-cycle stage → generation trait (recommended) |
| 778 | Gymnosporangium juniperi-virginianae (telial) | Rust spore stage | rust life-cycle stage → generation trait (recommended) |

## Data inventory (2026-10-02)

Read-only queries against a production copy restored into local `gallformers_dev` (species last updated 2026-09-30).

| Area | Count |
|---|---|
| Gall rows | 4,094 (1,552 undescribed; 1,551 with a Gallformers Code) |
| Distinct described inducer names | ~2,440 |
| Names with both an agamic and a sexgen row | 76 (619 agamic and 253 sexgen rows overall) |
| Undescribed galls by genus link | 927 to placeholder genera; 625 to a real genus |
| Plants | 2,575 real + 159 genus placeholders; 2,554 with WCVP/POWO IDs; 171 WCVP "no_match" |
| Higher taxa | 1,615 rows (263 families, 1,230 genera, 12 sections, 7 intermediate ranks) + 103 placeholders |
| Stored iNat taxon IDs | None |
| Host links | 8,734 (228 to placeholders; 78 galls have only placeholder hosts; 1 gall has none) |
| Aliases | Scientific: 2,229 on galls, 588 on plants. Common: 287 on galls, 835 on plants |
| Sources | 927; 8,195 record-level links (8,189 to galls), 8,074 with narrative; Source 58 on 1,323 galls |
| Gall range | 232,390 rows for 3,509 galls; 44 confirmed |
| Host range | 1,081,537 rows for 2,625 plants; 89,328 of them on 86 placeholders |
| Images | 7,663 on galls (5,365 from iNat); 17 on plants |
| Non-gall records | 120 |
| Keys | 4 |
