---
status: raw
created: 2026-11-07
updated: 2026-11-07
epic: taxogall
relates: [6611, 294c, f14c, c90c]
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


## Status (2026-11-07, evening)

**Pipeline (items 1, 2, 4): committed `171c326e`.** The guides name each value of an "X or Y" Trait term (one Fact per value; an unstated side of the leaf stays `leaf`; `null` only for wording that leaves the value open). Producer and checker summaries name the value they hold or argue for. Phase 1 joins the pieces Docling's HTML reader splits a web paragraph into (`merge_inline`, `convert.py`), so a quote can be the sentence. A v6 run of the five trial Sources started overnight (`services/import-producer/output/v6-2026-11-07/`, log `output/run-v6.log`), each scored against the golden set.

**Back end (items 3, 5, 6, 7, 8): built, `mix precommit` clean, not committed.**
- **3:** a format 4 Trait dispute carries `subject["facts"]`, `["suggestions"]` (the producer's categories) and `["placements"]` (each checker's), as a term's covers do (`Import.Disputes`). The producer and the checkers already gave their values as data (`category` in `gall.json`, `placements` in `review.json`), so no contract change was needed.
- **5:** `GallMatcher`: an undescribed Gall that has no candidate on its Hosts while a Host is still unresolved waits on that Host (`"waits_on_host"`, no queue item of its own; matched again once the Host is decided). Otherwise it looks at the undescribed entries of the Inducer's genus on other plants of its Hosts' genera (the ID tool's index). Those whose code holds an epithet of the Source's Host names are offered first, then those sharing descriptive words. None is firm. When such entries exist but none matches, nothing is proposed. On package 97: toothed rosinweed (g20) now gets *Antistrophus s-dentatum-cryptic-stem-gall* as its best match; Horkelia (g46) waits on its Host; sunflower (g45) gets 5 candidates on Helianthus; mossy bramble (g48) gets one candidate on Rubus.
- **6:** "Create a new Gall" is never firm (`Import.Proposals`: weak), and neither "Create it as a new Gall" nor "It depends on the Gall" is a firm proposal in `Questions`.
- **7:** a dispute about a Fact that a Trait term question covers is asked in that question: its findings join the use's `"findings"`, it has no item of its own, and the question proposes nothing (`TraitTerms.absorb_disputes/2`). A disputed Fact whose term is already placed stays a dispute.
- **8:** a per-Gall answer (`"categories"`) that gives every covered Gall the same values, for a new term or one fitting none, is recorded as `"place"` (`TraitTerms.remembered/2`), so no later Source asks again. A Gall may now take several values (`%{"g1" => ["green", "yellow"]}`). The vocabulary page already places terms (the old backlog's "map" is gone), so nothing is needed there.
- **9:** moved to `c90c`.

**Found while checking package 97 (data for Jeff):** two names are each held by two taxa. "Silphium dentatum" is accepted species 4878 and also a synonym of Silphium asteriscus var. dentatum (4863, which is placed directly under the genus). "Horkelia congesta" is accepted 5190 and also a synonym of Potentilla congesta (4870). The resolver takes the accepted one with no question, which is why toothed rosinweed's Gall (on 4863) didn't match.

