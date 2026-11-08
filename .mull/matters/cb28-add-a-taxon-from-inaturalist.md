---
status: raw
created: 2026-11-08
updated: 2026-11-08
epic: taxonomy
relates: [e1d2, 8ba0, f923, 6611]
---

# Add a taxon from iNaturalist

Jeff, 2026-11-08, reviewing package 119 (InfluentialPoints): the Source's Host "Rubus villosus var. frondosus" is, per WCVP, a synonym of *Rubus pensilvanicus* Poir., which WCVP leaves Unplaced; iNat places the group in *Rubus* sect. Arguti (https://www.inaturalist.org/taxa/1449402). We hold neither, and the review can't add an Unplaced WCVP record or answer a Host question with a section. Rather than adding taxa by hand on the New Taxon page, Jeff suggests importing a taxon from iNaturalist, as observations are imported (`Curation.from_observation/3`, matter `ec2c`).

## The idea

Paste an iNaturalist taxon link or ID; Gallformers reads the taxon (`/v1/taxa/:id`): its name and rank, its ancestors, its common name, its iNat ID. It shows where it would go in our tree (the nearest ancestor we hold, the missing ones between) and adds the taxon, and any missing ancestors, under them. The taxon keeps its iNat ID (the mapping `e1d2` wants).

## Where it's used

- The import review's Host question: "Add a new plant" gains "from iNaturalist…" beside the New Taxon page, so a Host the Source names that WCVP can't place is added in place.
- The taxonomy admin's New Taxon page.
- Plants and animals alike (iNat holds both; WCVP only plants).

## To decide with Jeff

- **Authority.** Taxonomy is credited to the literature; Gallformers is the authority only as a rare exception. Whose statement is the placement: iNaturalist as a database Source, the reference iNat's taxon cites (its taxon framework), or the Source that prompted it (here InfluentialPoints)? Ties to `f923` (taxonomy as Facts) and the taxonomy admin's "Based on which Source?" (`TaxonomyLive.BasisPicker`).
- **WCVP first for plants?** When WCVP holds the plant, WCVP's record and placement win; iNat only fills what WCVP lacks (sections, Unplaced names)? Or iNat for sections and below only?
- **Ancestors.** Add missing ancestors automatically, or one at a time with a look?
- **Through the tray** (`d3b0`, one ingestion path) as a Gallformers change, like the other admin edits?

## Related, in the review

- The Host question's plant search lists only species and below, so it can't answer with a section even once one is held (`Taxa.Search.plants/2`); a section is offered only for a common-name Host.
- WCVP Unplaced records can't be added or searched (`HostDecisions`, `HostSuggestions` treat Unplaced as doubtful; `Wcvp.Lookup.search/2` lists Accepted only).


## Decided (Jeff, 2026-11-08)

- **Credit iNaturalist for the placement.** The taxon's placement (and any ancestor added with it) is a statement credited to iNaturalist.
- **No "winning" between WCVP and iNat.** Curators own the taxonomy; WCVP and iNat are tools to populate it. WCVP is generally the default for plants; iNat is a real boon as a second tool (sections, names WCVP leaves Unplaced, animals).
- **Ancestors, rearranging, children.** Importing a taxon fills in its missing ancestors; it can also rearrange the tree around it and add its children. My reading, to confirm when this is designed: importing *Rubus* sect. Arguti offers to move the species we hold that iNat places in it (e.g. *Rubus allegheniensis*) under it, and to add its children from iNat that we don't hold, each one the curator's choice, credited to iNat.


## Exploration (2026-11-08)

### What iNat gives (public v1 API, no login)

- `GET /v1/taxa/:id`: name, rank, `is_active`, `parent_id`, every ancestor (id, name, rank), its children (id, name, rank, active), the preferred common name, observation count. No authorship: iNat doesn't carry authors.
- `?all_names=true`: every name, by lexicon: scientific names (valid and not, so its synonyms) and common names in many languages.
- `GET /v1/taxa?q=` and `/v1/taxa/autocomplete`: search by name, with `matched_term` when a synonym matched. Searching "Rubus pensilvanicus" returns sect. Arguti (1449402), matched on that name: iNat treats it as a name within Arguti. Arguti's ancestors: Plantae › Tracheophyta › Angiospermae › Magnoliopsida › Rosales › Rosaceae › Rosoideae (subfamily) › Rubeae (tribe) › Rubus (genus) › Rubus (subgenus) › Arguti (section); its children are ~30 species, among them *Rubus frondosus* (Leafy-bracted Blackberry), likely what InfluentialPoints means by "Rubus villosus var. frondosus".
- Ranks iNat uses that we have: all of ours (kingdom … form). Ones we don't: complex, subsection, zoosection, epifamily, hybrid and the like: skipped, the taxon attached to the nearest one we have.
- Limits: 60 requests a minute is plenty (one import is a handful); a generic app User-Agent, never a person's contact details. Taxonomy and names are facts, not licensed media; no photos here.

### What we already have to build on

- `Import.TaxonomyAdmin.create_taxon/4` creates a taxon and moves `child_ids` under it (rearranging) in one audited transaction, every edit through `Import.record_taxonomy_edit/2` (the replay log).
- `TaxonomyAdmin.add_plant_from_wcvp/3` adds a plant and the family or genus it needs: the ancestor-filling pattern.
- The Host question's "Add a new plant ↗" and the taxonomy admin's New Taxon page are the two places to start an import.
- Taxa carry an `origin` (`:curated`, `:powo`) and, for plants, a WCVP link; there is no iNat link yet (`e1d2`). Crediting a placement to a Source as a Fact is Phase 2 (`f923`).

### Sketch

1. **Find:** paste an iNat link or ID, or search by name (the Source's name; the match says which taxon and through which name).
2. **Look:** the taxon, its rank and common name, its iNat link; its lineage beside our tree (each ancestor: we have it, missing, or we have it somewhere else); its children (we have it under another parent: move it; we don't: add it); its other scientific names (as synonyms).
3. **Choose and add, as one change:** the taxon with the ancestors needed to attach it, the children and synonyms ticked; each edit in the replay log; the iNat taxon ID kept on every taxon it adds or touches.
4. **Authorship** comes from WCVP when WCVP holds the name (plants); otherwise blank for the curator.


## Decided (Jeff, 2026-11-08, on the sketch)

1. **Credit:** create an iNaturalist database Source now, ready for Phase 2 (`f923`); until then taxa it adds are marked as from iNaturalist (a new `origin` beside `:curated` and `:powo`) and keep their iNat taxon ID.
2. **Ancestors:** those needed to attach the taxon ticked; the higher gaps iNat has and we don't (adding them would move taxa we hold) offered unticked.
3. **Children:** all unticked by default; the curator ticks what to move or add.
4. **Names:** the scientific synonym that matched the search ticked, the others not; iNat's preferred English common name comes along.
5. **Inducers too:** offered from the review's name questions as well as Host questions. WCVP has no insects or mites, so for Inducers and their associates iNat is the only such tool.

## A second motivating case (package from Floate 2010)

"Which taxon does Floate 2010 mean by “Syrphidae”?": a family we don't hold, with no higher taxon to attach it to (the Source names it only as "(Diptera: Syrphidae)"). Today the only answer is to add it unplaced and place it from the taxonomy admin later. With this feature: search iNat for "Syrphidae" from the question, and bring in its tree (Animalia › Arthropoda › Insecta › Diptera › … › Syrphidae), the ancestors we lack ticked down to the one we hold.

