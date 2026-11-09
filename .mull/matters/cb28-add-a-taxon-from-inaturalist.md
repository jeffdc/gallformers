---
status: planned
created: 2026-11-08
updated: 2026-11-08
epic: taxonomy
relates: [e1d2, 8ba0, f923, 6611]
---

# Add a taxon from iNaturalist

# Add a taxon from iNaturalist

From a review question (and later the taxonomy admin), find a taxon on iNaturalist, see it beside our tree, choose what to bring in (the taxon, the ancestors it needs, its children, its names), and add it in one change credited to iNaturalist; the question is then answered with that taxon. Designed with Jeff on 2026-11-08; mockup approved the same day ("this looks good"): `/dev/mockups/inat-taxon` (`?case=host`, `?case=family`).

## Why

Two review questions with no good answer today:

- **Package 119 (InfluentialPoints):** the Host "Rubus villosus var. frondosus". WCVP calls it a synonym of *Rubus pensilvanicus* Poir., which WCVP leaves Unplaced, so it can't be added from WCVP; we hold neither. On iNaturalist, "Rubus pensilvanicus" is a name within *Rubus* sect. Arguti (1449402), whose species include *Rubus frondosus*.
- **Floate 2010:** "Syrphidae" (Diptera), a family we don't hold, with nothing above it to attach it to. Today it can only be added unplaced.

WCVP covers only plants; iNat covers plants and animals, sections and names WCVP can't place.

## Decided (Jeff, 2026-11-08)

- **Curators own the taxonomy.** WCVP and iNaturalist are tools to fill it in; neither "wins". WCVP is the usual default for plants; iNat is a second tool beside it, and the only one for insects, mites and other animals.
- **Credit iNaturalist** for what an import adds: a database Source per day of access ("iNaturalist, accessed 8 Nov 2026"), dated that day, made on the day's first import and reused after, so an import competes by the day it was made.
  - **Non-plant taxa:** each placement, name, synonym and common name is that Source's taxonomic statement, accepted at once by the curator importing (the taxonomy admin's path since `f923` Task 8).
  - **Plants:** plant taxonomy is edited directly, following WCVP, with no statements (`8567`; `f923` covers non-plant taxa only). A plant added from iNat is marked as such (a new `origin`, `:inaturalist`) and keeps its iNat ID.
- **Ancestors:** those needed to attach the taxon (the missing ranks between it and the nearest one we hold) are ticked; ranks above the nearest one we hold are folded into one line ("Plantae › … › Rosales · 5 ranks above it we don't hold · Show them"), unticked. Our tree starts at family in places (Rosaceae, Cecidomyiidae have no parent): when we hold nothing above the taxon, it goes in at the top, as our families do.
- **Children:** listed, all unticked; one we hold under another parent can be moved under it ("we have it under Rubus · Move here"), one we don't hold added.
- **Names:** the scientific synonym that matched the search ticked, the other synonyms unticked; iNat's preferred English common name ticked, the others unticked.
- **Authorship:** for each taxon added, WCVP's when WCVP holds the name, else an empty field (iNat carries none).
- **Ranks we don't use** (complex, subsection, zoosection, hybrid…): skipped in the lineage; when the taxon itself has one (Alleghenienses is a "complex"), the curator picks the rank to add it as.
- **A reusable tool whose main caller is the review.** About 90% of edits come in through ingestion and its review; the Fact viewer and editor (`87a1`) is a separate tool for on-the-fly edits, not merged with this.
- **One search, not two.** The question's own search answer searches every tool at once, results grouped:
  - **Host questions**, "Another plant…": "Search Gallformers, WCVP and iNaturalist by name." Groups: In Gallformers (Use this), WCVP (Add it), On iNaturalist (Look at it).
  - **The other name questions** (Which taxon is it; Names we don't have; Names we have for more than one species), "Another taxon…": "Search Gallformers and iNaturalist by name." Groups: In Gallformers, On iNaturalist.

  An iNaturalist result's "Look at it" opens the import panel on that taxon; "← Other results" closes it back to the search. No separate "Find it on iNaturalist…" answer.
- **The panel:** in the rail's place over the review (`gf-sheet`), a bottom sheet on phones.
- **Wherever WCVP is offered for plants, iNat is offered beside it:** the review's plant search (above); the New Taxon page ("From iNaturalist" beside "From POWO-WCVP"); a taxon's edit page (linking it to its iNat taxon beside its WCVP link; the ID only, WCVP stays the source of Host ranges).

## The panel (`inat_taxon_panel`, as the mockup draws it)

- Head: "From iNaturalist", Close.
- **Find** (only when opened without a search, e.g. from the New Taxon page): a live search field ("A name, or an iNaturalist link or number"); when iNat has nothing for a name, the names WCVP gives for it offered as one-click searches. Each result: name and rank, common name, observations ("22,268 observations"), "Matched “…”, a name iNaturalist files under it" when a synonym matched; "Look at it".
- **Look and choose:** the taxon (name, rank), its common name, observations, "iNaturalist ↗"; "We have it: the import links it and adds what you tick" when we do. **Where it goes**: the folded line for the ranks above, then each rank from the nearest we hold down ("We have it" / "Add: needed to attach it" ticked / "Add" / "A rank we don't use"), the taxon last ("Added" or "We have it"). **Under it on iNaturalist** (count): the first 8, held ones first, "Show N more". **Names**: synonyms ("synonym · the name that matched"), common names ("common name · iNaturalist's"). **Authorship**: a field per taxon added, "From WCVP" when filled from it.
- Foot: the credit line (plants: "Marked as from iNaturalist, with its iNaturalist ID. Plants are edited directly, so no statements are recorded."; others: "Each is iNaturalist's statement (iNaturalist, accessed 8 Nov 2026), accepted by you."), the primary button saying what it does ("Add 2 taxa and 2 names"; "move N" when moving), Cancel, and "Then the question is answered with Arguti."
- After Add, the question is decided with the taxon (a Host with the Source's spelling as its synonym, as "Another plant…" does) and the review moves on with "Saved: …".

## Design

- **Client:** `Gallformers.INaturalist.Taxa`: `search/1` (`/v1/taxa/autocomplete`, with `matched_term`), `fetch/1` (`/v1/taxa/:id?all_names=true`: ancestors, children, names, `is_active`, `current_synonymous_taxon_ids`); Req with the existing retry and test stub (`Req.Test`, `config/test.exs`); a generic app User-Agent, never a person's contact details. Well under iNat's limits (a handful of requests per import).
- **Plan:** `Gallformers.Import.InatTaxa.plan/2` (the iNat taxon, the matched name) → the taxon (held: by its iNat ID, else its name at its rank in its kingdom, `Taxa.resolve_name/2`), the lineage rows (held, needed, higher, skipped), the children (held under which parent, or not), the names, WCVP authorship (`Wcvp.Lookup.find_names/1`), what is ticked. An inactive iNat taxon offers the one that replaced it.
- **Write:** `InatTaxa.carry_out/3` (actor, plan, the curator's choices) → `{:ok, %{taxon_id, added, moved}}`, all or nothing, every edit in the replay log:
  - non-plants: `Import.TaxonomyStatements.record/3` with the day's iNaturalist Source as the basis: `{:create_taxon, attrs, child_ids}`, `{:place, …}` / `{:move_all, …}`, `{:name, …}` (authorship), `{:add_synonym, …}`, `{:add_common_name, …}`;
  - plants: `Import.TaxonomyAdmin.create_taxon/4`, `record_taxonomy_edit/2` (`{:place, …}`, `{:add_common_name, …}`), `record_synonym_added/4`, origin `:inaturalist`;
  - both: the iNat ID set on every taxon added or matched.
- **Data:** the iNaturalist Source (`Sources.inaturalist_source/1`, by date); `origin` `:inaturalist` (the `taxa_origin_check` constraint); a `taxon_inaturalist` table (taxon ID, iNat taxon ID) beside `taxon_wcvp`, set by a new replay-logged edit `{:set_inat, taxon, id}`: `e1d2`'s mapping.
- **UI:** one LiveComponent (find, look, choose) taking a starting taxon or name, telling its caller `{:imported, taxon_id}`; catalog entry `inat_taxon_panel` (Approved once Jeff signs off the build plan), placed with `gf-sheet`.
- **The review:** the question's search answer (`Answer`'s `:plant` and `:taxon` pickers) gets the iNat group; a Host question's Gallformers group also lists sections and genera (today's plant search lists species and below only, `Taxa.Search.plants/2`, so an imported section couldn't be picked); "Look at it" opens the panel; `{:imported, taxon_id}` decides the question as the Gallformers result would.

## Out of scope (v1)

Photos; observations and ranges from iNat; keeping taxa in step with later iNat changes (`8ba0`'s "taxonomic change tracking"); importing a whole subtree beyond one taxon's children; common names other than English. WCVP Unplaced records stay un-addable from WCVP (iNat is the way in for them).

## Tasks (failing test first in each)

1. **Data:** the per-day iNaturalist Source; origin `:inaturalist`; `taxon_inaturalist` and `{:set_inat}` (replay log).
2. **Client:** `search/1`, `fetch/1` against stubbed responses recorded from the real API (Arguti 1449402, *Rubus frondosus* 168056, Syrphidae 49995, Alleghenienses 1449411, an inactive taxon).
3. **Plan:** taxon held or new; lineage rows and what's ticked (Arguti: subgenus *Rubus* needed, Rosoideae and Rubeae higher; Syrphidae: nothing held, all higher); children held elsewhere or not; names; WCVP authorship; a rank we don't use (the taxon's own, and in the lineage); an inactive taxon.
4. **Write:** a plant (editorial path, origin, iNat ID) and an animal (statements credited to the day's iNaturalist Source, accepted); children moved and added; all or nothing; replay; a second import of the same taxon matches it and adds nothing twice.
5. **The component** (`inat_taxon_panel`): catalog entry, style-guide entry, component and LiveView tests (the steps, ticks, the button's words, `{:imported, id}`).
6. **The review:** the iNat group in "Another plant…" and "Another taxon…"; sections and genera in a Host question's Gallformers group; the panel in the rail's place; the question decided on import. LiveView tests on both cases.
7. **The taxonomy admin:** "From iNaturalist" on the New Taxon page (the panel's find step); "Link to iNaturalist" on a taxon's edit page.
8. **Check on real data:** 119's Rubus Host (sect. Arguti, or *Rubus frondosus*), Floate 2010's Syrphidae, at desktop and phone. Then delete the mockup and its route (`docs/design-system/mockups.md`).

## Related

`e1d2` (the taxon ↔ iNat ID mapping this builds), `8ba0` (iNat integration), `f923` (taxonomy as Facts), `8567` (plants the exception), `6611` (the review), `c8c3`.

