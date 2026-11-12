---
kind: question
text: 'Check cb28 on real data: package 119''s Rubus Host (Arguti) and Floate''s Syrphidae, after b230 Tasks 1-4 (items eb66, 11dc, 7378, e7ef, bceb).'
plan: taxogall
source: matter cb28, 'What's left (2026-11-09)'; replaces entry 2cb4
by: /Users/jeff/dev/gallformers
created: "2026-11-12T02:23:22Z"
---

What cb28 built (on taxogall, e69af545; the `taxon_inaturalist` migration is applied to `gallformers_taxogall`): from a review question, and from the taxonomy admin, find a taxon on iNaturalist, see it beside our tree, choose what to bring in (the taxon, the ancestors it needs, its children, its names), and add it in one change credited to iNaturalist; the question is then answered with that taxon. Its last task, the real-data check, was never run (the builder couldn't use the shared dev databases).

The two cases, the review questions that had no good answer before:
- Package 119 (InfluentialPoints): the Host "Rubus villosus var. frondosus". WCVP calls it a synonym of *Rubus pensilvanicus* Poir., which WCVP leaves Unplaced, so it can't be added from WCVP; we hold neither. On iNaturalist "Rubus pensilvanicus" is a name within *Rubus* sect. Arguti (1449402), whose species include *Rubus frondosus*. Expected (cb28's plan tests): "Another plant…" finds it in the On iNaturalist group; the panel shows Arguti with subgenus *Rubus* ticked as needed to attach it, Rosoideae and Rubeae above it folded and unticked; Add decides the question with the taxon (a Host with the Source's spelling as its synonym), Arguti or *Rubus frondosus*.
- Floate 2010: "Syrphidae" (Diptera), a family we don't hold, with nothing above it to attach it to. Expected: nothing above it held, so it goes in at the top as our families do, its higher ranks folded and unticked; as a non-plant, each placement and name is the day's iNaturalist Source's statement, accepted by the curator.
Try both at desktop and phone width (the panel takes the rail's place, a bottom sheet on phones).

Why wait for b230 Tasks 1-4: they change how the review reaches the panel (one shared search, Task 3; the panel's Add hands its taxon back to the card and the import runs inside the decision, so Undo takes it back, decision 6 and Task 4).

While trying it, settle the built defaults filed as decisions in this inbox (the cb28 'conservative choices': an inactive taxon, a rank we don't use, children of such a rank, held names, WCVP authorship, the button's words, the folded ranks line, the Find step's wording, the iNat links, the New Taxon and edit page wording, the day's Source, the requests). Once checked, cb28's work is complete.
