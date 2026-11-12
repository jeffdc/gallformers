---
plan: taxogall
phase: db43
title: One answer list and the in-place 'Add it by hand'; the iNat panel hands its choice back
stage: committed
docs:
  - .mull/matters/b230-review-cleanup-one-way-to-handle-a-name-we-don-t-have-and-the-2026-11-09-audit.md
created: "2026-11-09T20:38:17Z"
updated: "2026-11-12T02:23:22Z"
---

**What:** every question about a name we don't hold (or can't place) offers the same answers in the same order, from one builder in `GallformersWeb.Admin.Review.Questions`. "Add it by hand…" opens in place, replacing the "Add a new plant ↗" link. The iNat panel in the review hands its choice back to the card instead of importing at once. This is b230's Task 4 (finding A "answers", and the iNat-hint bug in finding C). It builds on the one decision shape and carry-out (item 11dc: `{taxon_id}` | `{wcvp_id}` | `{inat: …}` | `{new: …}` | `{skip}`) and on the one search in `GallformersWeb.Choices` (item e7ef), which is its "Find it…". References are as of `65531d59` (`questions.ex` lines after about 241 are +1 since); go by function names.

**Why.** In Jeff's walk-through of the new review (2026-11-09), a name we don't have was handled differently on every question. The Host question offered "Search…" and "Add a new plant ↗", which do the same job. The related-taxon question (a parasitoid, say) looked and worked like a different screen. The audit found the suggestions built twice: `host_targets`/`host_target` (questions.ex about 1635-1720) and `taxon_choices`/`shown` (about 1921-1949). "Another plant…" and "Another taxon…" are two builders (`another_plant` about 1521, `another_taxon` about 2067).

**The answers, in this order, for every name question:**
1. **The suggestions**, if any: "Use X", marked Suggested or Best guess, with the same identity line everywhere.
2. **Find it…:** one search, results grouped. In Gallformers (for a Host, genera and sections too). WCVP (plants only; picking one adds it from WCVP). On iNaturalist (picking one opens the iNat panel; its Add answers the question).
3. **Add it by hand…**, in place: the name, its rank and its parent (the genus filled in when we hold it). For a plant at species rank or below, its Host range too.
4. **Leave it out.**

A common-name Host keeps its two extra answers: "A section of X" and "Only the genus".

**Where it applies:** the Host questions. Also: which taxon is it (`:called_new`, `:not_held`, `:several_species`); the synonym questions; a Host dispute read as another plant; a hedged Host statement's "Add it…"; and the missed names' "Add a statement…" (the "Names we didn't read" card).

**Jeff's decisions this rests on (2026-11-09):**
- **(1) A plant added by hand at species rank or below needs its Host range**, asked for in place, as the New Taxon page does.
- **(6) The iNat panel in the review hands its choice back to the card.** Its Add no longer imports at once: the chosen taxon (with its ticks) becomes the answer, and the import runs inside the decision. So a refused decision leaves nothing and Undo takes the import back. This settles cb28's open question 13: today Undo reopens the question but the taxa, names and links the panel brought in stay. On the New Taxon page the panel still imports at once.

**Build:**
- **One builder in `Questions`** for a name question: suggestions (one identity line), "Find it…", "Add it by hand…", "Leave it out". Its settings: `kind: :plant | :taxon`, `common_name?`, sections and genus.
  - It replaces `host_targets`/`host_target`/`taxon_choices`/`shown`/`another_plant`/`another_taxon`/`create_taxon`.
  - **The hint mentions iNaturalist only where iNat is searched.** This fixes a bug (finding C): the hint "Search Gallformers, WCVP and iNaturalist…" (questions.ex about 1525-1537, 2070-2072) shows on `ItemRow` pages, which never search iNat. Only `QuestionCard` turns on `inat: true` (question_card.ex about 61). Once `ItemRow` is retired (item f926), iNat is searched everywhere.
- **"Add it by hand…" opens in place.** Fields: name (prefilled with the Source's spelling), rank, parent, and for a plant at species rank or below the Host range (the existing range editor, `TaxonomyLive.RangeEditor`, as the New Taxon page uses it).
  - The parent's genus is prefilled once, by one prefill replacing `Questions.held_genus` and `Loader.plant_genus`.
  - Delete "Add a new plant ↗" (`QuestionCard` about 376-386, `ItemRow` about 428, `ReviewComponents` about 644), `ReviewComponents.new_plant_href/1` and `Loader.new_plant`.
  - Decides with `{new: %{name, rank, parent_id, range?}}`.
- **The iNat panel in the review returns its choice to the card** (decision 6), and the card decides with `{inat: …}`. Today `ReviewLive.Review` hides the rail and shows `InatTaxonPanel`. The panel imports, tells the LiveView `{InatTaxonPanel, {:imported, taxon_id}}`, and the card gets it by `send_update` (`imported:`) and decides through `Answer.decide_imported/3`. Delete `Answer.decide_imported/3` and the import-then-decide path. The panel, opened from the review, ends by handing back the taxon and the curator's ticks instead of carrying out the import. On the New Taxon page it keeps importing at once.
- **Every place in "Where it applies" uses the builder:** the dispute read as another plant, the hedged Host's "Add it…", and the missed names.
- **`Choice` carries a `leave?` flag.** It replaces `QuestionCard.leave_host?`, which recognises the answer by its wording, "Leave this Host out" (question_card.ex about 460; finding G).
- **The catalog follows.** The `review_card` entry in `docs/design-system/components.md` says "A Host nothing matches offers Search…, Add a new plant… ↗ and Leave this Host out". Update it to the four answers.

**Calls:** `GallformersWeb.Choices` (the search from item e7ef), `Import.decide_queue_item/3` through `ReviewLive.Answer` (the only web caller `.credo.exs` allows), `TaxonomyLive.RangeEditor`.
**Deletes:** `Questions.host_targets`/`host_target`/`taxon_choices`/`shown`/`another_plant`/`another_taxon`/`create_taxon`/`held_genus`, `Loader.plant_genus`/`new_plant`, `ReviewComponents.new_plant_href/1` and the "Add a new plant ↗" links, `Answer.decide_imported/3`, and `QuestionCard.leave_host?`.

**Tests (first, watched failing):** a LiveView test per question kind that the four answers show in order and each decides. Check the Host and parasitoid cards against each other. The iNat panel in the review decides with `{inat: …}`, and Undo removes what it brought in.

**Done when:** every question in "Where it applies" offers the same four answers from one builder. "Add a new plant ↗" is gone. The iNat panel in the review hands its choice back. `mix precommit` is clean, and the duplicate-code baseline is lowered (never raised) if findings dropped.

From matter b230, Task 4 (Jeff's decisions 1 and 6). Settles cb28's open questions 9 and 13. Sizing is the intake's guess: if it doesn't fit one session, mull ask to split it.

Before Model v2 this item needed e7ef. Items have no needs now; order work with needs between phases.
