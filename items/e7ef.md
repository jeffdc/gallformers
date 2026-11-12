---
plan: taxogall
phase: db43
title: One name search in GallformersWeb.Choices
stage: committed
docs:
  - .mull/matters/b230-review-cleanup-one-way-to-handle-a-name-we-don-t-have-and-the-2026-11-09-audit.md
created: "2026-11-09T20:38:17Z"
updated: "2026-11-12T21:00:11Z"
---

**What:** `GallformersWeb.Choices` (`lib/gallformers_web/choices.ex`) becomes the one place that runs and words a name search. Every caller below moves onto it, and its own search code is deleted. This is b230's Task 3 (findings A "searches", E and F "searches"). It comes after the back end's decision shape (item 11dc) and before the one answer list (item bceb), whose "Find it…" answer is this search. References are as of `65531d59` unless noted; go by function names.

**Why: what the audit found.**
- **`ReviewLive.Answer.search` has five branches** (answer.ex about 380-456). "plant" behaves three ways there. `:plant` gets Host choices, WCVP and iNat. `{:reading, _}` and `:statements` get plants and sections only. `:statement` gets plants only.
- **The WCVP search is written three times:** Answer (about 436-452), `TaxonomyLive.New` (`taxonomy_live/new.ex` about 125-140) and `InatTaxonPanel.wcvp_names`. The **parent search is written twice:** Answer (about 394-407) and new.ex (about 204-215).
- **"Only the genus…"** (questions.ex about 1622) searches every taxon unfiltered.
- **The Gall editor** (`gall_live/editor.ex` about 297) **and the taxon edit page** (`taxonomy_live/edit.ex` about 332) call `Taxa.search_plants` directly for their qualifier searches.
- **The shared search isn't shared (E).** `Answer.plant_hits(:plant)` (about 461-470) and `Choices.hosts/2` (choices.ex 23-31) both wrap `Taxa.host_choices`, worded and grouped differently. `Answer.taxon_meta`/`aliases` (about 558-565) duplicate `Choices.meta/2` (49-53). There are two place searches: Answer's `"place"` uses `Places.search_places`, and `Choices.places/3` uses `Places.search_fact_places`. `trait_values(definitions, trait)` is written three times: `source_live/facts.ex` about 336, `review_live/facts.ex` about 407-408 and `gall_live/fact_actions.ex` about 595-596. "Readers' values first" is written twice: `QuestionCard` about 586-592 and Answer about 1157-1162.
- **Two iNat searches (F).** The card's (Answer about 507-541) and the panel's Find (`inat_taxon_panel.ex` about 150-162) differ in minimum length (3 against any), in how they test "matched" (Answer about 525 against `ReviewComponents.inat_matched?`, about 2835) and in wording.

**Build: `Choices` runs and words every name search.**
- **Groups:**
  - **In Gallformers:** taxa; for a Host, plants plus genera and sections. A Host's "Another plant…" must list genera, subgenera and sections, so that an imported section can be picked. `Taxa.Search.plants/2` alone lists species and below.
  - **WCVP:** plants only. Picking one adds it from WCVP.
  - **On iNaturalist:** one iNat search, from 3 characters, with one "matched" test and one wording. Picking one opens the iNat panel.
- **A parent search** filtered to ranks above, with the genus prefilled.
- **The meta line** ("rank · also a, b").
- **`trait_values/2,3`** and "readers' values first".
- **One place search:** pick between `Places.search_places` and `Places.search_fact_places` while building, and say which in the hand-back.
- **Function names `.credo.exs` expects** (`SingleEntryPoint`, the owners table from c800): `Choices.wcvp_plants/2` for the WCVP name search (`Wcvp.Lookup` / `wcvp_lookup()` `search/2` and `search_contains/2`) and `Choices.inat_taxa/1` for the iNat taxon search (`Import.search_inat_taxa/1`, `INaturalist.Taxa.search`). `Choices` already owns the Host choices (`Taxa.host_choices/2`).
- **How the review's search looks.** This was cb28's question 9, now settled here. The search keeps the `typeahead`, whose mechanics may not change (`docs/design-system/README.md`). iNat results are a group of its results, with "Look at it" in the row. An empty or still-loading group isn't shown. iNat is searched from 3 characters, as WCVP is: once per search, debounced, beside WCVP. cb28's wording is "Search Gallformers, WCVP and iNaturalist by name." for a Host (groups: In Gallformers "Use this", WCVP "Add it", On iNaturalist "Look at it"), and "Search Gallformers and iNaturalist by name." for the other name questions (groups: In Gallformers, On iNaturalist). There is no separate "Find it on iNaturalist…" answer. Wherever WCVP is offered for plants, iNat is offered beside it.

**Callers that move onto `Choices`:**
- `ReviewLive.Answer`: replace `plant_hits`, `section_hits`, `taxon_meta`/`aliases` and its WCVP and iNat code (`inat_search`, `inat_results`, `inat_result`), and its place search.
- The iNat panel's Find (`GallformersWeb.Admin.InatTaxonPanel`, its `found/1` calling `Import.search_inat_taxa/1`).
- The New Taxon page (`TaxonomyLive.New`): its WCVP search (`wcvp_lookup().search(limit: 10)`, about new.ex:134 as of `a0434bcf`) and its parent search.
- **`TaxonomyLive.RangeEditor`**, from `.credo.exs`, which lists it as a pending b230 caller of the WCVP name search. b230's Task 3 doesn't name it. As of `a0434bcf` it calls `wcvp_lookup().search_contains/2` twice in `range_editor.ex`: in `"refresh_from_wcvp"` when no WCVP record matches (`{:nomatch, name, search_contains(name, limit: 20)}`), and in `"wcvp_nomatch_search"` (from 2 characters, limit 20). It's a contains search with its own minimum, so `Choices.wcvp_plants/2` has to serve it.
- The Gall editor's and the taxon edit page's qualifier searches (`Taxa.search_plants` today).
- The review and Source Facts pages (`review_live/facts.ex` and `source_live/facts.ex`, for `trait_values` and their plant searches). Item a81c deletes `review_live/facts.ex`, so if that has landed, only its moved code remains.
- The Fact inspector's pickers (the 87a1 code: `gall_live/fact_actions.ex`, `gall_live/from_observation.ex`). Jeff's decision 7 (2026-11-09): everything in this cleanup is done here, including the parts in the Fact inspector's code. Splitting them off would repeat the fragmentation this cleanup fixes.

**Not here:** `InatTaxonPanel.wcvp_names` (the WCVP names offered when iNat has nothing). Finding A counts it among the three WCVP searches, but it calls `find_names`/`get_names` rather than `search`, so `SingleEntryPoint` doesn't cover it. b230's Task 7 (item 5e0c) moves that read through `Import` with specific rescues.

**Guardrails.** In `.credo.exs`, `SingleEntryPoint` fails when a pending module no longer makes the call, so remove each pending entry in the same change that moves its caller. The entries to clear:
- WCVP name search: `ReviewLive.Answer`, `TaxonomyLive.New`, `TaxonomyLive.RangeEditor`.
- iNat taxon search: `ReviewLive.Answer`, `InatTaxonPanel`.
- Host choices: `ReviewLive.Answer`.

Never add an entry or an owner. Owners change only by Jeff deciding to.

**Calls:** `Taxa.host_choices/2`, `Wcvp.Lookup.search/2` and `search_contains/2` (through `wcvp_lookup()`), `Import.search_inat_taxa/1`, `Places.search_places`/`search_fact_places` (one of them), `Taxa.search_plants`.
**Deletes:** `Answer.plant_hits`, `section_hits`, `taxon_meta`, `aliases` and its WCVP, iNat and place search code. Also New Taxon's WCVP and parent searches, RangeEditor's direct `search_contains` calls, and the copies of `trait_values` and "readers' values first".

**Tests (first, watched failing):** `Choices` unit tests per group (In Gallformers with genera and sections for a Host, WCVP, On iNaturalist with its 3-character minimum and "matched" test, the parent search, places). For each caller, a LiveView test that its search lists the groups it should.

**Done when:** every name search in the callers above runs through `Choices`, and the search code they had is deleted. `.credo.exs` has no b230 pending entries for the WCVP search, the iNat search or the Host choices. `mix precommit` is clean, and the duplicate-code baseline is lowered (never raised) if findings dropped.

Also from matter c800, Task 2 (the owners and pending table), and matter cb28, open question 9 and 'What's left (2026-11-09)'.

From matter b230, Task 3. The 2026-11-09 audit adds: include TaxonomyLive.RangeEditor (.credo.exs lists it as pending on b230), and name the Choices functions .credo.exs expects, one for WCVP plants and one for iNat taxa. Clear the b230 pending entries in .credo.exs once the callers use Choices. Sizing is the intake's guess: if it doesn't fit one session, mull ask to split it.

Before Model v2 this item needed 7378. Items have no needs now; order work with needs between phases.

**Added 2026-11-12 (Jeff): a Host is always placed.** Jeff: we always place a Host (a match to one we hold, an alias of one we hold, an import from WCVP or iNat, or a manual entry) rather than leave it unresolved. So a WCVP name WCVP leaves Unplaced can be added as a Host like any other WCVP name. Today `host_suggestions.ex` refuses it (about lines 83 and 528, "can't be added from it"); the one WCVP search this item builds offers it, and its line says WCVP leaves it unplaced.
