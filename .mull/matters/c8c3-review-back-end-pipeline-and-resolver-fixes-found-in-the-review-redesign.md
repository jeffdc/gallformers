---
status: done
created: 2026-11-07
updated: 2026-11-08
epic: taxogall
relates: [6611, 294c, f14c, c90c, ca45]
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


10. **Singular and plural are different terms** (Jeff, 2026-11-08, package 115). Nastasi & Davis's "swelling" (form, 3 Galls, `ambiguous`: already known to mean different values in different Galls) and "swellings" (form, 15 Galls, `new`) are two Trait-term questions, because terms are grouped and looked up in the term mappings by exact text. Treat singular and plural (and other inflections) as one term when grouping a Source's terms and when matching term mappings, so the curator decides "swelling" once for all 18 Galls and a later Source writing either form takes the decision.


11. **A Trait dispute can only be kept or dropped** (found building `6611`, 2026-11-08). `Import.Disputes` takes `%{"keep" => true}` (the producer's values) or `%{"skip" => true}` (the Source's words as text). The approved review card treats a Trait dispute like a Trait term: "Keep as text", or "Map it to <trait> values" with every value of the Trait, each side's values pre-ticked (the producer's `suggestions`, the checkers' `placements`). When the curator ticks values other than the producer's (a checker's, or their own), there is no decision to send. The dispute needs a values decision, e.g. `%{"values" => [v, …]}` (or the term's `%{"categories" => %{gall_ref => [v…] | nil}}` for its one Gall), writing the Fact with those values as `keep` writes the producer's. Until then the review offers, on a Trait dispute, only "Keep as text" and the producer's values.


12. **A name the producer missed can't be acted on** (Jeff, 2026-11-08). `Import.UnusedNames` lists the taxon names a Source prints that we hold but no batch declares (Osten Sacken's "Cynips quercus inanis"). The old overview showed the list; the new review doesn't, because Jeff: "if we show it we have to be able to action it". Needed: from a listed name, send its passages back through the producer (a partial run of one Source, adding to its package), so the missed Gall or taxon comes back as statements and questions like the rest. Each such run is a paid producer run and needs Jeff's go. Once it exists, the review shows the list just before Approve (a rail line like the hedged statements, opening a card of names with their pages and Read the Source), each with that action.


13. **A named species with one Gall is asked about only because the Source names no generation** (Jeff, 2026-11-08, package 115: Nastasi & Davis's "silverpuff stem gall (Antistrophus microseris)", and we have one Gall for *A. microseris*). When the species has a single Gall and isn't known to alternate generations, the match should be firm (or not asked), not a "Which Gall?" question that holds approval. A species that does alternate could still be describing the missing generation's Gall, so only those should ask. Needs a way to tell whether a species alternates (its Galls' generations, the genus, a Trait), which is the back end's call.


## Status (2026-11-08): items 10–13

**10 built (uncommitted):** `TraitTermMapping.normalize/1` takes each word's plural as its singular ("swellings" → "swelling", "covered in short hairs" → "covered in short hair", "berries" → "berry", "patches" → "patch"). Words ending in ss/us/is ("hairless", "glabrous"), words of three letters or fewer, and a few that only look plural ("species", "this") are left alone. The folded form is only a key and is never shown. Every term comparison goes through this one function: grouping a Source's terms, looking up the term table, pending terms, set-aside items, and the ID tool's term search. Migration `20261109120000_fold_term_plurals` recomputes the stored keys (term table, pending terms, term candidates, and Trait-term and set-aside queue refs). It merges terms that fold together into the oldest row: if they agree it keeps them as they are, otherwise the term becomes ambiguous between all their values. Run on a copy of `gallformers_taxogall`, it merged "swelling" and "swellings" (both ambiguous) and folded the refs. Where one batch held both forms, the second keeps its old ref until the package is resolved again. The replay log finds a question logged under an old ref (`TraitTerms.current_ref/1`). Only plurals are folded, not other inflections ("swollen", "-ed", "-ing").

**11 built (uncommitted):** a Trait dispute also takes `%{"values" => [v, …]}`: one or more values of its Trait, none twice. Decided before apply, its Facts go on them (`Disputes.chosen_values/1` joins the apply context's `trait_values`; a curator's Fact edits still win). Decided after apply, they are written and the waiting term is settled under them. The decision replays. The review session (6611) sends it from the Trait card.

**13: the diagnosis was wrong.** Silverpuff stem gall (g11, *Antistrophus microseris*) wasn't asked because of the generation. The lone-candidate rule is already firm unless the species alternates generations (heterogony group) or the Source conflicts with the Gall. It was asked because of a **form conflict**: the Source's "swellings" read as `tapered swelling`, while Gall 1445 then held only `abrupt swelling`. Approving package 115 has since added tapered swelling to it. Proposed fix, waiting on Jeff: compare forms coarsely, as plant parts are compared. Values that are the candidates of one ambiguous form term ("swelling": abrupt swelling, tapered swelling, stem club) count as `differ`, not `conflict`. The rule comes from the term table, not a hard-coded list. Separately: should a single-Gall species that doesn't alternate be firm even with a real form or plant-part conflict?

**12: waiting on Jeff (design and paid runs).** See the questions in the session; outcome to be recorded here.


**Decisions (Jeff, 2026-11-08):**
- **10 and 11 committed** (`14c67ffb`). The fold-plurals migration has run on `gallformers_taxogall` and `gallformers_dev`.
- **13:** forms that are readings of one ambiguous form term differ, not conflict (built, uncommitted). `GallComparison.source_side/3` adds `form_near`, read from the term table by `Catalog.trait_readings_with/2`. Silverpuff stem gall's case (tapered vs abrupt swelling) would now be resolved firmly. A real form conflict still asks.
- **12:** no producer re-run for a missed name. Jeff: it's far too powerful a tool for such a small scope. How a listed name is acted on is still to be discussed.

- **12 back end built (uncommitted until the review handles the kind).** `Import.MissedNames`: resolving queues one `:missed_name` item per name `UnusedNames` lists, on the gall batch (`n:<normalized name>`). It never holds approval and has no proposal. Decisions: `%{"dismiss" => true}`, or `%{"state" => %{"kind" => "inducer_of" | "host_of", "taxon_id", "gall_id", "items"}}`, which writes one Relationship Fact on a Gall Gallformers holds. It is attributed to the package's Source, with the name as written and the chosen blocks as whole-item evidence. It's written when the gall batch is applied, or at once if it already is, and it replays. Migration `20261109130000_add_missed_name_queue_kind`. `UnusedNames` now prints a name without the punctuation after it ("Quercus douglasii", not "Quercus douglasii."). Review side: the 6611 session adds the card (Not needed / Add a statement… in the 87a1 editor).


## Done (2026-11-08)

All committed on `taxogall`: items 1, 2 and 4 in `171c326e`; 3, 5, 6, 7 and 8 in `50435243`; 10 and 11 in `14c67ffb`; 12 (back end) and 13 in `20782866`. Both migrations have run on `gallformers_taxogall` and `gallformers_dev`. Item 9 is `c90c`. The "Add a statement…" form for a missed name is the review's (`6611`).


**Item 13 follow-up (Jeff, 2026-11-08):** a species with one Gall that doesn't alternate generations still goes to the curator when the Source really conflicts with that Gall (form or plant part). Only close forms count as `differ`. That is how it works already, so nothing changes.

