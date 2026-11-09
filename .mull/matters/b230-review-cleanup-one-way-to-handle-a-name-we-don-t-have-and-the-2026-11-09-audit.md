---
status: planned
created: 2026-11-09
updated: 2026-11-09
epic: taxogall
relates: [6611, cb28, c800, 87a1, c8c3]
---

# Review cleanup: one way to handle a name we don't have, and the 2026-11-09 audit

## Why

Jeff's walkthrough of the new review (2026-11-09) found that a name we don't have is handled differently on every question: the Host question offers "Search…" and "Add a new plant ↗", which do the same job, and the related-taxon question (a parasitoid, say) looks and works like a different screen. Two read-only audits followed, one mapping every unknown-name path and one looking for duplicated or dead code across the 6611, cb28 and 87a1 commits. This matter holds what they found, Jeff's decisions, and the plan to fix it. It takes over 6611's Task 10 (retire the old pages). How this happened, and the guardrails against it, are in `c800`.

File and line references are as of `65531d59` on `taxogall`. Abbreviations: Q `lib/gallformers_web/admin/review/questions.ex`; A `lib/gallformers_web/live/admin/review_live/answer.ex`; QC `…/review_live/question_card.ex`; IR `…/review_live/item_row.ex`; RC `lib/gallformers_web/components/review_components.ex`; QU `lib/gallformers/import/queue.ex`; HD, GD, SD `lib/gallformers/import/{host,gall,synonym}_decisions.ex`; IT `lib/gallformers/import/inat_taxa.ex`; TA `lib/gallformers/taxonomy_admin.ex`.

## The mechanic we want

Every question about a name we don't hold (or can't place) offers the same answers in the same order:

1. **The suggestions**, if any: "Use X", marked Suggested or Best guess, with the same identity line everywhere.
2. **Find it…**: one search, results grouped: In Gallformers (for a Host, genera and sections too); WCVP (plants only; picking one adds it from WCVP); On iNaturalist (picking one opens the iNat panel; its Add answers the question).
3. **Add it by hand…**, in place: the name, its rank and its parent (the genus filled in when we hold it). For a plant at species rank or below, its Host range too. This replaces the "Add a new plant ↗" link.
4. **Leave it out.**

A common-name Host keeps its two extra answers ("A section of X", "Only the genus").

Behind them: one answer builder, one search, one decision shape, and one carry-out run inside the decision. Whatever the decision creates (from WCVP, from iNat, by hand) is created when the curator decides and logged with the decision, so Undo takes it back and a refused decision leaves nothing behind.

**Where it applies:** the Host questions; which taxon is it (`:called_new`, `:not_held`, `:several_species`); the synonym questions; a Host dispute read as another plant; a hedged Host statement's "Add it…"; the missed names' "Add a statement…". Outside the review, the New Taxon page and the Fact inspector's plant pickers use the same search.

**Real differences, kept as settings:**
- Plants are editorial; other taxa are Source statements (the Source under review, the day's iNaturalist Source, or the basis picked on the New Taxon page).
- WCVP is for plants only.
- A common-name Host never becomes a synonym and may resolve to a genus or section.
- A Host reading records the Source's sense of the name (sensu).
- A Host above species rank goes in as `host_taxon_id`, with no reading.

## Jeff's decisions (2026-11-09)

1. **A plant added by hand at species rank or below needs its Host range**, asked for in place, as the New Taxon page does.
2. **A new non-plant taxon is created when the curator decides**, credited to the Source under review, not later at apply time.
3. **The Source's spelling becomes a synonym for every name**, Host or not (a common-name Host still never does). An earlier idea to exempt OCR errors is dropped.
4. **Retire `ItemRow`:** the notes page, the taxonomy queue and Renames move onto the new card.
5. **Dead code goes.**

6. **The iNat panel in the review hands its choice back to the card.** Its Add no longer imports at once: the chosen taxon (with its ticks) becomes the answer, and the import runs inside the decision, so a refused decision leaves nothing and Undo takes the import back (this settles cb28 open question 13). On the New Taxon page it still imports at once.
7. **Everything in this matter is done here,** including the parts in the Fact inspector's code (87a1): its pickers, its photo picker, its reading-fix checks and its missing-input wording. Splitting them off would be the same fragmentation this matter fixes.
8. **The notes page's "Needs you" tab draws each held note's questions as the Everything view's rows** (`review_question_row` around `QuestionCard`, review.ex:834-864), so a question looks the same everywhere.
9. **The Facts edits go on the review's last step:** its Facts list (`facts_view`) gets the Facts page's per-Fact menu (Drop, Change Host, Change value, Note) with the shared `fact_editor` under the Fact, and Undo under each edit. (The review mockup doesn't draw these.)

## The audit's findings

The task that removes each is in brackets.

**A. One name, many paths** [Tasks 2-4]
- **Creating a taxon, five ways:**
  1. Host: a link out to the New Taxon page (QC:376-386, IR:428, RC:644; prefill `Loader.new_plant`/`plant_genus` loader.ex:1154/1189).
  2. Non-Host: an in-place `{:parent, rank}` picker, created at apply time by `ApplyTaxonomy.create_new_taxon` (apply_taxonomy.ex:222, apply_gall.ex:242), origin `:curated`.
  3. Synonym split: at decide time, editorial even outside Plantae (SD).
  4. The New Taxon page (`TA.create_taxon`, TA:51).
  5. The iNat panel: imports before and outside the decision (IT:382), so a refused decision leaves the taxon.
- **The back end refuses `new` for `:unresolved_host`** (QU:227-230) but accepts it for an ambiguous Host (QU:232), which the UI never offers.
- **Suggestions built twice:** `host_targets`/`host_target` (Q:1635-1720) and `taxon_choices`/`shown` (Q:1921-1949). "Another plant…"/"Another taxon…" (Q:1521/2067) are two builders.
- **Searches:**
  - `A.search` has five branches (A:380-456). "plant" behaves three ways: `:plant` gets Host choices, WCVP and iNat; `{:reading,_}` and `:statements` get plants and sections only; `:statement` gets plants only.
  - WCVP search is written three times: A:436-452, `taxonomy_live/new.ex:125-140` and `InatTaxonPanel.wcvp_names`.
  - The parent search is written twice: A:394-407 and new.ex:204-215.
  - "Only the genus…" (Q:1622) searches every taxon unfiltered.
  - The Gall editor (`gall_live/editor.ex:297`) and the taxon edit page (`taxonomy_live/edit.ex:332`) call `Taxa.search_plants` directly.
- **The spelling and synonym helpers, three times:**
  - `HD.spelling`/`add_spelling`/`holds?` (HD:139/159);
  - `GD.written_out`/`ensure_synonym` (GD:334/353);
  - `Loader.expand_genus` (loader.ex:1180).

  All end in `Import.record_synonym_added`. Only Host decisions, Host readings and `synonym_of` add a spelling today.
- **Duplicate checks, three times:** new.ex:526 `duplicate_warnings`, `HD.held_plant` (HD:201) and `IT.held`.

**B. Old pages still running** [Task 5]
- `ReviewLive.Step` (373 lines) and `ReviewLive.Facts` (600 lines) are still routed (router.ex:143-147), and nothing links to them.
- Components only they use: `review_step_bar`, `review_step_head`, `review_step_foot`, `review_step_done` and `review_source_head` (RC:946-1275).
- `SourcePage`'s moduledoc describes the deleted overview.
- About 3,000 lines of tests drive the step URLs: the names, galls, disputes, hedges, trait_terms, step, question, source_text, titles, undo and facts tests.
- The dry run is written twice: `Review.preview`/`dry_run` (review.ex:333-349) crashes on an error; `Facts.load_facts` (facts.ex:113-132) handles errors and merges several packages.

**C. Two question UIs** [Task 6]
- `ItemRow` is live on `/admin/review/notes` (source.ex:343), the taxonomy queue (taxonomy.ex:272) and Renames (renames.ex:112).
- **The Trait answer is written twice:**
  - `ItemRow.term_galls` (IR:551-603), with Answer's `galls` state, `pick_gall`/`fill_galls` (A:214-227), `effect_for(:galls)` and `choice_decision(:galls)`;
  - `QuestionCard.trait_answers` (QC:481-584), with `trait_decision` (QC:172-218).

  The two send different decision shapes.
- **The note box:** `review_notes` (RC:2117-2139) and a copy inside QC:283-301.
- **Undo:** IR shows the refusal with its link; `Review` (review.ex:181-193, 556-558) shows the text only.
- **Old wording still live:** "Recommended", "To check", "Reject the recommendation" and "No recommendation" (IR:425-660).
- **A bug:** the iNat hint ("Search Gallformers, WCVP and iNaturalist…", Q:1525-1537, 2070-2072) shows on IR pages, which never search iNat. Only QC turns on `inat: true` (QC:61).

**D. Dead code** [Task 1]
- **The settle follow-up:**
  - In Answer: the "settle" event (A:114-139), `settle` in `@events` (A:46), `settled` state (A:65) and its reset (A:102-105), `sections?(:statements)` (A:502-503), `plant_sections(:statements)` (A:328), `choice_decision(:statements)` (A:613-636), `effect_for(:statements)` (A:754-770), `picker(:statements)` (A:1006-1027) and the picker's `settled` attr (A:976).
  - Its callers: QC's `:settled`/`:galls` ctx (QC:318-319, 425) and IR's `settled=` (IR:425).
  - In Questions: `picked_decision(%Choice{picker: :statements})` (Q:627-656) and the `{:statements, …}` type (Q:241).
  - In Choice: `statements` and the `:statements` picker (choice.ex:13, 60, 93, 109, 137).
  - In the components: `review_settle_list`/`settle_options` (RC:893-941).
- **The `"pick_galls"` handler** (A:205-211): nothing sends it.
- **`review_step_overview`** (RC:1102-1180).
- **`SourcePage.approval_text/1` and `and_list`** (source_page.ex:125-138).
- **`Loader.stats/1`** (loader.ex:637-654) and `SourcePage`'s `stats:` assign (source_page.ex:74).
- **`Import.fact_statements/1`** (import.ex:877): only the `fact_edit_mock.ex` mockup calls it. The mockups stay until Jeff has looked at the real UI, so the mockup keeps its own copy.

**E. The shared search isn't shared** [Task 3]
- `A.plant_hits(:plant)` (A:461-470) and `Choices.hosts/2` (choices.ex:23-31) both wrap `Taxa.host_choices`, worded and grouped differently.
- `A.taxon_meta`/`aliases` (A:558-565) duplicate `Choices.meta/2` (choices.ex:49-53).
- There are two place searches: `A.search("place")` uses `Places.search_places`; `Choices.places/3` uses `search_fact_places`.
- `trait_values(definitions, trait)` is written three times: source_live/facts.ex:336, review_live/facts.ex:407-408 and gall_live/fact_actions.ex:595-596.
- "Readers' values first" is written twice: QC:586-592 and A:1157-1162.

**F. iNat duplicates** [Tasks 3 and 7]
- **Two iNat searches:** the card's (A:507-541) and the panel's Find (inat_taxon_panel.ex:150-162). They differ in minimum length (3 against any), in how they test "matched" (A:525 against RC:2835 `inat_matched?`) and in wording.
- **Copied helpers:**
  - `inat_observations` (RC:2844-2853) copies `Helpers.format_number/1`.
  - `@inat_italic`/`inat_italic?` (RC:2377, 2833) and seven inline italic spans re-implement `taxon_name` (data_display_components.ex:45) and lose its upright "var."/"×".
  - `InatTaxonPanel.refusal/1` (inat_taxon_panel.ex:206-228) re-implements `TaxonomyLive.Errors.text/1` and leaves "%{count}" unfilled.
- **Rank parsing:** `InatTaxa.our_rank` (IT:190) and `InatTaxonPanel.rank_of` (inat_taxon_panel.ex:143). The same `Enum.find(Rank.all(), …)` appears 9 times in the repo; add `Rank.parse/1`.
- **iNat URLs built in several places:**
  - taxa: `inaturalist/taxa.ex:140`, `taxonomy_live/edit.ex:899`;
  - observations: `inaturalist.ex:115`, `curation_components.ex:324`, and `FactsComponents.observation_href`/`observation_name` (facts_components.ex:1797-1807), which copies `CurationComponents.observation_url`.
- **Other duplicates:**
  - `INaturalist.Taxa.result/1` and `taxon_result/1` build the same map (taxa.ex:72-94).
  - `parse_taxon_id` returns `{:ok, int} | :error`, while `parse_observation_id` returns `{:ok, string} | {:error, :invalid_input}`.
- **Boundary drift:**
  - The panel calls `Wcvp.Lookup` itself with `rescue _ -> []` (inat_taxon_panel.ex:189-204).
  - The function component calls `InatTaxa.counts`/`additions`/`rank_choices` directly (RC:2558-2566).
  - `inat_taxon_panel` lives in ReviewComponents, though the New Taxon page uses it too.

**G. Design system** [Task 8]
- Raw link buttons where the built `button variant="link"` should be: RC:1496, 1504, 1678, 1694, 1754, 1764 and 1787; review.ex:750; QC:561.
- Hand-rolled panels instead of `panel`: `card_class` with `p-6` (RC:1780), the rail's aside with `p-panel` (RC:1439), and Review's fallback unit (review.ex:810).
- "Names we didn't read" is drawn as `review_card kind={:hedges}` with its heading overridden (review.ex:731-741). Give it its own kind.
- The section heading is written inline twice (review.ex:831, RC:1684).
- `QuestionCard.leave_host?` recognises an answer by its wording "Leave this Host out" (QC:460). Choice should carry a flag instead.
- The Fact inspector's photo picker in from_observation.ex:303-330 copies `InatImportComponent`'s grid (inat_import_component.ex:160-220).

**H. Tests** [Task 9]
- **Copied fixtures:**
  - question_card_test.exs:1-89 copies galls_step_test.exs:1-91.
  - review_test.exs:77-161 copies trait_terms_test.exs:38-118.
  - `rubus_tree` is written five times: inat_taxa_plan_test:24, inat_taxa_write_test:47, inat_taxon_panel_test:32, review_live/inat_test:54, and taxonomy_live/inat_test:30-31.
  - About ten hand copies of `open_row`/`choose`/`visible_text`.
- **"Postgrex … client exited" noise:**
  - In the review, from the dry run (review.ex:333-341) and the Host WCVP read (A:280-295), which tests don't `render_async`.
  - Also in gall_live_edit_test (L147-218, L368) and gall_live_observation_test (L174), likely TrayLive's `{:change_set, _}` refresh (tray_live.ex:131). Not pinned down.

**I. The same thing defined two ways** [Task 10]
- Two reading-fix checks: `FactHistory`'s `p.key LIKE 'reading-%'` (fact_history.ex:62-100, 145-160) against `content->'source' ? 'reading_of'` (reading_fixes.ex:34, source_dates.ex:34).
- Two reading-fix spec builders: `FactActions.specs({:reading,…})` (fact_actions.ex:150-163) and `SourceLive.Facts.fix`/`reading_to`/`correction` (source_live/facts.ex:237-290).
- Missing-input wording differs: A:714-734 and source_live/facts.ex:285-290 against fact_actions.ex:191-221. 6611 decided "Search…" for a name and "Choose…" for a value.
- The hedged sections are listed three times: units.ex:51, review.ex:49 and IR:113. `Units.hedged?` also counts missed names (units.ex:194).
- **Counts:** `Units` claims every count comes from `tally/1`, but Approve uses `SourcePage.approval` through `Steps.summarize` (source_page.ex:62, 93). `Units.stages` (units.ex:116-140) recomputes what `Steps.summarize` (steps.ex:133-146) computes.
- **`inat` names three things:** `Choice.inat` (choice.ex:98), Answer/QC state `inat: true` (A:67, QC:61) and Review's `inat` assign (review.ex:72). New Taxon also has `inat_open` (new.ex:75, 260), and Answer sends `{:inat_open, …}` (A:176).
- **Doc drift in components.md:**
  - `fact_editor` cites the removed `Loader.host_choices/2`.
  - The `review_rail` entry's attrs and events are out of date.
  - The `review_card` entry describes keys that aren't built.
- **Doc drift elsewhere:** mockups.md says there are no mockups, but six exist. Misplaced comments in Answer (A:243, 637, 819, 1049, 1107) and a duplicated doc (A:899-900).

**J. Waste** [Task 10]
- `Loader.missed_context`/`missed_taxon` (loader.ex:1122-1145) reloads each taxon's context per entry on every reload. Batch it like `taxa_info` (loader.ex:878-885).
- `Review.notes_source?` (review.ex:96) builds the whole notes page to read the Source's kind.

## The plan

Every task: write the failing tests first and watch them fail; then build. Precommit clean. Commit on `taxogall` (in the main checkout; Jeff says when). A task that replaces something deletes it in the same task. Each task starts in a fresh session from this matter.

### Task 1: Delete the dead code (D)
Remove everything under D, with its tests if any (none reference the settle flow). Precommit proves nothing used it. Also fix `Review.dry_run` crashing on an error: use the Facts page's error handling, kept for Task 5.

### Task 2: One name decision in the back end (A: decisions, creation, spelling)
- **One decision shape** for a name: `{taxon_id}` | `{wcvp_id}` | `{inat: %{id, ticks…}}` | `{new: %{name, rank, parent_id, range?}}` | `{skip}`, plus `sensu` for a reading.
  - `QU.choices` accepts it for `:unresolved_host`, an ambiguous Host, `:unresolved_name` and the `:ambiguous_match` kinds. Remove "A Host is never created by import" (QU:227-230).
- **One carry-out**, run inside `decide_queue_item`'s transaction, branching on kingdom:
  - A plant goes through `TA.create_taxon` / `add_plant_from_wcvp` / `IT.carry_out`, editorial, with the Host range required at species rank or below.
  - Any other taxon becomes a statement of the Source under review (decided at decide time, decision 2), or of the day's iNaturalist Source for an iNat import.
  - What it creates is logged in the decision's `carried_out` entry, so `Undo.reversal` takes it back. Check that `Undo` reverses each kind of creation and extend it where it doesn't.
  - `ApplyTaxonomy.create_new_taxon` and `ApplyGall`'s copy then only read the decision.
  - The synonym split (SD) creates a non-plant species as a statement too.
- **One spelling helper** (a new `Import.Spelling` or in `HD`; decide while building): the Source's spelling with its abbreviation expanded, "already holds it", and `record_synonym_added` with an optional sensu.
  - It replaces `HD.spelling`/`add_spelling`/`holds?`, `GD.written_out`/`ensure_synonym` and `Loader.expand_genus`.
  - It runs for every name decision except a common-name Host (decision 3).
- **One duplicate check** for "do we already hold this plant/taxon", used by New Taxon, HD and IT.
- **`Rank.parse/1`**, replacing the 9 copies.
- **Tests:** every decision shape on every kind, including a refused decision leaving nothing behind, and Undo removing what each created. Replay (`Import.Replay`) logs and replays the new shapes.

### Task 3: One search (A: searches; E; F: searches)
- `GallformersWeb.Choices` is the one place that runs and words a name search. Groups: In Gallformers (taxa; for a Host, plants plus genera and sections), WCVP (plants), On iNaturalist (one iNat search, minimum 3 characters, one "matched" test, one wording).
  - A parent search filtered to ranks above, with the genus prefilled.
  - The meta line ("rank · also a, b").
  - `trait_values/2,3` and "readers' values first".
  - One place search: pick between `search_places` and `search_fact_places` while building, and say which.
- **Callers:** Answer (replacing `plant_hits`, `section_hits`, `taxon_meta` and its WCVP/iNat code), the iNat panel's Find, the New Taxon page (WCVP and parent searches), the Gall editor and taxon edit qualifier searches, the review and Source Facts pages, and the Fact inspector's pickers (decision 7).
- **Tests:** `Choices` unit tests per group; each caller's LiveView test that its search lists the groups it should.

### Task 4: One answer list and the in-place add (A: answers; C: the hint bug)
- **One builder in `Questions`** for a name question: suggestions (one identity line), "Find it…", "Add it by hand…", "Leave it out", with settings `kind: :plant | :taxon`, `common_name?`, sections and genus.
  - It replaces `host_targets`/`host_target`/`taxon_choices`/`shown`/`another_plant`/`another_taxon`/`create_taxon`.
  - The hint says iNaturalist only where iNat is searched (after Task 6, everywhere).
- **"Add it by hand…"** opens in place: name (the Source's spelling), rank, parent (genus prefilled; one prefill, replacing `held_genus` and `Loader.plant_genus`), and for a plant at species rank or below the Host range (the existing `range_editor`).
  - Delete "Add a new plant ↗" (QC:376-386, IR:428, RC:644), `new_plant_href` and `Loader.new_plant`.
- **The iNat panel in the review** returns its choice to the card (decision 6); the card decides with `{inat: …}`. Delete `Answer.decide_imported/3` and the import-then-decide path.
- **Every place in "Where it applies"** uses the builder: the dispute read-as-another-plant, the hedged Host's "Add it…", missed names.
- **`Choice` carries a `leave?` flag**, replacing `leave_host?`'s wording match (G).
- **Tests:** a LiveView test per question kind that the four answers show in order and each decides. Host and parasitoid cards are checked against each other.

### Task 5: Retire the step and Facts pages (B; 6611 Task 10)
- **The Facts edits on the review's last step** (decision 9): per-Fact Drop, Change Host, Change value and Note through `fact_editor` and `Import.edit_fact/5`, Undo under each. The dry run is `Facts.load_facts`'s, with several packages merged and errors handled, replacing `Review.dry_run`.
- **Port the step and facts tests' decision flows** to `question_card_test`/`review_test`. Then delete `Step`, `Facts`, the step components and the step tests.
- **Redirect** `/review/sources/:id/:step`, `/review/packages/:package_id/:step` and the `/facts` URLs to the review.
- `Steps` stays (Units uses it). Fix `SourcePage`'s moduledoc.

### Task 6: Retire ItemRow (C)
- **Move the notes page's "Needs you"** (decision 8), **the taxonomy queue** and **Renames** onto `review_question_row` + `QuestionCard`.
- **Delete:**
  - `ItemRow`;
  - its components: `review_alias`, `review_ask`, `review_comparison`, `review_decide_bar`, `review_decided`, `review_definitions`, `review_identity`, `review_new_plant`, `review_read_source`, `review_technical`, `review_voices` and `review_segmented`;
  - Answer's `galls`/`text_value`/`default_value` branch;
  - QC's inline note box (use `review_notes`).
- **Undo** shows its refusal with the link everywhere.
- **Fix the hedged section list** to be defined once (units.ex:51).
- **Tests:** the notes page, taxonomy and renames tests on the card.

### Task 7: The iNat helpers (F, other than the search)
- `format_number`, `taxon_name`, `TaxonomyLive.Errors.text`.
- One iNat URL module; one result map; `parse_taxon_id` shaped like `parse_observation_id`.
- The panel's WCVP read through `Import`, with specific rescues.
- The component no longer calls `InatTaxa`: the LiveComponent passes in what it shows.
- Move `inat_taxon_panel` to its own components module.
- Name the three `inat` things apart.

### Task 8: Design system (G)
- `button variant="link"` everywhere listed.
- `panel` for the hand-rolled ones.
- A `:list` kind for "Names we didn't read".
- One section-heading component.
- The Fact inspector's photo picker and `InatImportComponent` share one photo grid (thumbnail, tick, license). It isn't a catalog component yet: write its catalog entry for Jeff's approval before building it.
- Run the conformance test, then lock the gain in with `mix gallformers.design_system.baseline`.

### Task 9: Tests (H)
- Move the copied fixtures into `ImportFixtures`, `INaturalistFixtures` and `AdminLiveHelpers`, and delete the copies.
- Find each "client exited" cause (`systematic-debugging`) and fix it: wait on the async work, or stop it at test exit. Precommit's log is free of them.

### Task 10: The rest (I and J)
- Counts from one place: Approve and the stages from `Units.tally` or `Steps.summarize`, one of them; say which.
- `Units.hedged?` stops counting missed names.
- Doc drift fixed: components.md entries, mockups.md, Answer's misplaced comments.
- The `missed_context` read batched.
- `notes_source?` reads the Source's kind directly.
- One test of what a reading-fix package is (the package key or the Fact's `reading_of`: pick one and say why), used by `FactHistory`, `ReadingFixes` and `SourceDates`.
- One builder of the reading-fix spec, used by `FactActions` and `SourceLive.Facts`.
- One missing-input wording, as 6611 decided ("Search…" for a name, "Choose…" for a value), in Answer, `SourceLive.Facts` and `FactActions`.

## Order and size

Task 1 first; it's a day or less and shrinks what the rest touch. Tasks 2, 3 and 4 in that order: the back end, then the search, then the answers. Tasks 5 and 6 can swap. Tasks 7 to 10 are small and can go in any order after 6. The `c800` guardrails (the one-entry-point check) can be switched on as soon as Task 3 names the single search and Task 2 the single decide.
