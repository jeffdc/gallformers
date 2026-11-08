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

