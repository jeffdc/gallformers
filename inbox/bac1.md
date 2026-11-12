---
kind: decision
text: 'iNat panel: the button reads ''Add 2 names'' / ''Move 1 and add 2 names'' when there are only names or moves'
plan: taxogall
source: matter cb28, 'Open questions for Jeff' (conservative choices where the plan was silent); replaces entry 6559
by: /Users/jeff/dev/gallformers
created: "2026-11-12T02:23:22Z"
---

cb28 open question 6. The situation: decided with Jeff, the panel's primary button says what it does ("Add 2 taxa and 2 names"; "move N" when moving). The mockup didn't cover a change that adds no taxa, only names or moves.

What was built (`GallformersWeb.ReviewComponents.inat_add_label/3`): "Add 2 taxa and 2 names", "Add 1 taxon, move 1 and 1 name", "Move 1 and add 2 names", "Add 2 names", and "Use it" when it adds nothing.

The alternative: the mockup's pattern, which would have read "2 names".

Why the conservative choice: cb28 gives one reason for all its open questions: where the plan was silent, the conservative choice was taken, and each is easy to change.

Context: cb28 'Add a taxon from iNaturalist' is built on taxogall (e69af545). From a review question, and from the taxonomy admin's New Taxon and edit pages, a curator finds a taxon on iNaturalist, sees it beside our tree, ticks what to bring in (the taxon, the ancestors needed to attach it, its children, its names) and adds it in one change credited to iNaturalist. The panel is `inat_taxon_panel` (`GallformersWeb.ReviewComponents.inat_taxon_panel/1`, its state in the LiveComponent `GallformersWeb.Admin.InatTaxonPanel`); what it offers and what it writes are `Gallformers.Import.InatTaxa.plan/2` and `carry_out/3` (as of a0434bcf; b230 Task 7 moves the component to its own module). Jeff approved the design and mockup on 2026-11-08. Where they were silent the builder took the conservative choice, and cb28 says each is easy to change. These are the built defaults Jeff is to settle while checking cb28 on real data (package 119's Rubus Host, Floate's Syrphidae).
