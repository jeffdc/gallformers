---
status: raw
created: 2026-11-07
updated: 2026-11-07
epic: taxogall
relates: [6611, 294c, f14c]
---

# Review back end: pipeline and resolver fixes found in the review redesign

Found while redesigning the import review with Jeff (2026-11-07; design in `6611`, mockup `/dev/mockups/source-reading/97`, Nastasi & Davis 2022). Each of these made the review ask questions it shouldn't, or offer wrong answers; the mockup worked around some in the UI, but they belong in the pipeline or the back end. **Not to change in the review UI work** (Jeff): do them here.

## The AI pipeline (producer, checkers, their guides)

1. **"X or Y" Trait terms name no value.** `priv/import/PRODUCER_GUIDE.md` (~line 199) and `VERIFY_GUIDE.md` (~line 37): "Never guess between values. A term that offers a choice or leaves it open names none of them… one Fact with category `null`". So "Green or yellowish" (color) and "single-chambered or have many chambers" (cells) come out null, a checker objects, and the curator ticks green and yellow by hand. In Gallformers several values for a Trait mean the Gall can be any of them, so a term naming alternatives the Gall varies between should name each (one Fact per value), like "green-yellow" already does; `null` only for wording that leaves the value open or that the Source says is unknown. Both guides change together (the verifiers check against the same rule). Needs Jeff's yes on the wording; the contract is `294c`.
2. **Dispute summaries can mislead.** "fleshy" (Cinquefoil bud gall, texture): the producer's one-line summary ("The vocabulary's texture value for 'fleshy' is defined by juicy walls…") dropped the value it chose; its full reasoning says it mapped "fleshy" to `succulent` through an existing term mapping. Summaries must name the value chosen.
3. **A dispute should carry each side's value as data,** not only prose (the producer's category and each checker's), so the review can say "The producer mapped “fleshy” to succulent; a checker says it isn't a texture here" and pre-tick each side's values. The mockup reads the value out of the producer's reasoning (`` `succulent` ``).
4. **Quotes that are fragments.** Some evidence quotes are a bare name ("Aphis rubifolii" behind a Host statement of the InfluentialPoints Source, seen in the Fact inspector, `87a1`). A quote should be the sentence that states the Fact.

## Gallformers' resolver and back end

5. **Undescribed Galls are mis-proposed as new.** The resolver proposes "Create it as a new Gall" for Galls Gallformers holds: "Toothed rosinweed cryptic stem gall (Antistrophus sp.)" is *Antistrophus s-dentatum-cryptic-stem-gall* (the Source's text says "(S. dentatum)"); "Horkelia stem gall" is likely *Diastrophus p-congesta-stem-gall* (Horkelia congesta, formerly Potentilla congesta); "Southern dewberry stem gall" sits beside *Diastrophus r-trivialis-root-gall*. Sources name undescribed Galls by the Host's common name; ours are coded by the Host's epithet. Match on Inducer genus + resolved Host (and the Host binomial in the Source's text), re-match after Host questions are answered, and never propose "create new" while a Gall of that genus on that Host exists.
6. **"Create a new Gall" and a Trait term's "It depends on the Gall" are firm proposals,** so bulk accept takes them: the first can create duplicates, the second settles nothing (each Gall still needs its value). Neither should be firm (`GallformersWeb.Admin.Review.Questions`, `Import.accept_proposals/2`).
7. **One statement asked twice:** as a Trait term ("what does “on the leaf or petiole” mean?") and as a dispute about the same statement ("Should “on the leaf or petiole” go in as Ground-ivy gall's plant part?"). Ask once.
8. **A curator's mapping of a term isn't remembered** (already open in `6611`): mapping "Green or yellowish" to green and yellow should add a term mapping, so no later Source asks.
9. **The dry run at scale.** `Import.preview_package/2` takes 0.25–1 s for 49 Galls; a Source of ~570 Galls (Gagné 1989) may take 10 s or more, recomputed after every decision. Recompute only the Galls a decision touches.
