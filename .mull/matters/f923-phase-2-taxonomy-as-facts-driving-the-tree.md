---
status: planned
created: 2026-11-06
updated: 2026-11-08
epic: taxogall
relates: [cb28]
---

# Phase 2: taxonomy as Facts driving the tree

Phase 2 (50ff step 3, before release): the tree is driven by current taxonomic Facts. Background and rules: 8567 ("Taxonomy is Facts; phase 2 before release", plants the exception, a Source's taxonomic act never moves the tree by itself); schema 9449 §3 (`placement_facts`, `name_facts`, `synonymy_facts`, `split_facts`, `common_name_facts`; placement and accepted name use slots; recorded in phase 1, never moving the tree); curation front ends ec2c. Covers non-plant taxa only: plant data stays editorial.

## Decided

- **Which statements decide the tree (Jeff, 2026-11-06): the literature is the authority, gated by a curator.** A Source's taxonomic Fact (placement, accepted name, synonymy, rank, split) is credited to that Source and competes by the Source's own date (recency rule). A curator's **acceptance** decides whether it is in effect: recorded on that Source's taxonomic statement (who, when; audited, replayed); until accepted, a newer paper's taxonomic statement is recorded but doesn't count — the one "awaiting a curator" mark the standing respects, for taxonomic statements only. A question arises only when an unaccepted statement is newer than what is current; an older paper's differing statement is history. A retracted paper loses support and the tree falls back to the next accepted position automatically. Gallformers is a taxonomic authority only as a rare exception (an undescribed Gall's Inducer; a position no paper supports): then a Gallformers statement with a reason, competing by date.
- Rejected (A): only Gallformers' statements decide the tree, a Source followed by a Gallformers confirmation. Easier to build, but it credits the current value to Gallformers instead of the paper, lets the order of curator decisions (not the papers' dates) decide, and keeps a retracted paper's position current.
- **Today's tree is undated at cutover (Jeff, 2026-11-06).** Its placements, accepted names and synonymy become statements of the undated "Gallformers legacy data" Source, so any accepted dated Source outranks them and a backscanned paper that disagrees raises a curator question. Reason: the tree may hold errors and outdated positions, and only building the history from the Sources catches them. Other than undescribed Galls, Gallformers makes no taxonomic placement without a third-party Source. Rejected: Gallformers statements dated at cutover, which would outrank every earlier paper and turn recent revisions the tree never adopted into silent history.
- **Question volume (Jeff, 2026-11-06).** A disagreeing paper raises a question only if it is newer than the latest accepted paper for that taxon; older ones are recorded as history. When a curator accepts a paper, open questions about the same taxon from older papers close as history. Order of review changes only the number of questions, never the outcome. The backscan prefers newest first per group of taxa: `runbooks/source-intake.md`.
- **The tree is a copy kept in step with the Facts (Jeff, 2026-11-06).** The tree tables (`taxa`, `taxon_names`) stay what every page, search, Gall name and the API read. When a taxonomic slot's winner changes (an acceptance, a retraction, a Gallformers statement), one function rewrites the affected tree rows in the same transaction and proposes the Gall renames that follow (the reviewed rename flow, 86e7). A check rebuilds the tree from the Facts and reports rows that differ: run in tests and on demand in production. Rejected: computing the tree from Facts on every read (every reader changes; walking the tree gets slower).
- **The taxonomy admin no longer edits non-plant taxa directly; a change is credited to the Source it follows (Jeff, 2026-11-06).** A move, rename or synonym asks "Based on which Source?": an existing Source, or a new one created on the spot as a citation (title, authors, date). It is recorded as that Source's statement, already accepted (curator and time on the acceptance), and wins by the paper's date; when the backscan later brings the paper in, its statement matches and raises no question. If an accepted newer paper already decides that taxon, the edit says so at once instead of silently changing nothing. Only with no Source is it a Gallformers statement with a required reason (the rare exception). The screens can stay much the same. Plants still edit directly.
- **Gallformers is rarely a taxonomic authority (Jeff, 2026-11-06).** Earlier records said Gallformers would take its own position on taxonomic changes; that was a mistake and is scrubbed from 8567, 50ff, ec2c, 20e5 and the domain model.
- **Declining a paper (Jeff, 2026-11-06).** A curator who doesn't follow a newer paper's taxonomic statement declines it with a required reason, recorded on that Source's statement (who, when, why; audited, replayed). No Gallformers statement is written: the tree keeps following the latest accepted paper, so its position stays credited to the literature, and readers see the declined paper and the reason. A declined statement never counts unless a curator reopens and accepts it; a still newer paper still raises a question. A Gallformers restatement is only for a position no paper supports (e.g. a curator combining two papers' positions). Rejected: declining by writing a dated Gallformers statement, which credits the tree to Gallformers. 8567 and ec2c updated to match.
- **Taxonomy questions don't hold a Source's approval (Jeff, 2026-11-06).** Questions about which organism the Source means (name resolution) still hold approval: Galls and Hosts can't attach without them. Questions about following the paper's placement, accepted name or synonymy don't: after approval they stay open in one taxonomy queue across all Sources until a curator accepts or declines each (the volume rule closes older papers' questions there, whichever Source they came from). Facts attach to taxa, not to their place in the tree, so a Source's Gall Facts are right either way, and a hard taxonomic call doesn't stall the backscan. The Source's overview shows its open taxonomy questions with a link.
- **Splits (Jeff, 2026-11-06).** Nearly all Facts are about Galls, not the Inducer, so an accepted split changes each affected Gall's Inducer and nothing else: its other Facts and their Sources follow the Gall untouched, and its derived name changes through the reviewed rename flow (86e7). On accepting a split of A into A and B: (1) Galls the splitting paper covers settle from its own gall statements (its Inducer for that Gall, credited to the paper); (2) each remaining Gall on A becomes one curator question, "Which taxon induces this Gall now?" — A, B, or not known yet (stays on A, marked as following the name in its old broad sense, until a later Source settles it); (3) older Sources' attributions are never rewritten: they keep `name_as_written`, so readers see a 1950 paper said "A" for the broad A. Questions are per Gall, never per Fact.
- **Lumps (Jeff, 2026-11-06).** An accepted synonymy of B into A needs no questions: B's Galls get A as Inducer and their names update through the rename flow; only a name collision is flagged (existing flow).
- **Accepting per act or per paper (Jeff, 2026-11-06).** Each taxonomic act can be accepted or declined (with a reason) on its own; "Accept the rest of this paper" follows a preview of what it does to the tree (every move and rename, the Galls whose names change, the split questions it opens); acts already declined stay declined. Unlike trait terms (no accept-all), the judgement is usually about the revision as a whole, and act-by-act picking could leave the tree half-following a coherent treatment.
- **Phase 1 decisions carry over (Jeff, 2026-11-06).** A phase 1 "Follow the Source" decision counts as that statement's acceptance at cutover; it doesn't come back as a question.
- **Deletes are tabled** until phase 2 is settled (Jeff, 2026-11-06); the audit and the open question are in ec2c.


## Implementation Plan

**Goal:** the non-plant tree follows the current accepted taxonomic Facts; curators accept or decline Sources' taxonomic statements in one cross-Source queue; tree edits are credited to the Source they follow.

**Architecture:** Acceptance is a mark on a taxonomic attribution that `Facts.Standing` respects for `taxon_*` kinds (the Gallformers and legacy Sources need none). A Taxa listener on `Facts.Events` rewrites the tree tables from slot winners through the existing `Taxa` writers and `Tree` validator, so taxon events (move, rename, merge, split) drive Gall renames and split questions as today. A rebuild-and-compare check guards the copy.

**Tech stack:** Ecto/Postgres, Carbonite audit, replay log, Oban (none new), LiveView for the queue and admin.

**Where it starts (code map, 2026-11-06):** act Facts are recorded in phase 1 (`Taxa.ActFacts`, `ApplyTaxonomy.write_fact/4`) but nothing marks acceptance, nothing syncs the tree from Facts, the catalog migration empties the act tables and gives today's tree no Facts, Taxa has no rank/authorship/merge/split operations (`:merge`/`:split` events defined, never emitted), tree-changing review decisions are editorial edits not linked to the Source's act, queue items are per package, and applied Sources' taxonomic Facts aren't shown.

### Task 1: Acceptance and decline on taxonomic attributions
**Files:** migration (`attributions`: `accepted_at`, `accepted_by_user_id`, `declined_at`, `declined_by_user_id`, `decline_reason`; or a `taxonomic_decisions` table keyed by attribution — choose the one `Facts.recompute` can read cheaply); `lib/gallformers/facts.ex` (`recompute/1` selects the mark), `lib/gallformers/facts/standing.ex`; new `Facts.accept/3`, `Facts.decline/4`, `Facts.reopen/2`; replay kind migration + `import/replay*.ex`.
**Behavior:** for kinds `taxon_placement`, `taxon_name`, `taxon_synonymy`, `taxon_split`, `taxon_common_name`, an attribution counts only if accepted, or if its Source is Gallformers or the undated legacy Source. Declined never counts until reopened. Accept/decline/reopen are audited, replayed, recompute standings. Facts stays independent of Taxa (the gated kinds are data, not a Taxa call).
**Testing:** unaccepted newer statement leaves the older winner current; accepting it supersedes; declining keeps the older; reopen + accept; retraction of an accepted Source falls back; Gallformers/legacy count without acceptance; gall kinds unaffected.

### Task 2: Fact model gaps
**Files:** migrations; `taxa/act_facts/placement_fact.ex`, `name_fact.ex`.
**Behavior:** a root placement (`parent_id` null) for top ranks; `name_facts` gain `sensu` and `authorship` (normalized for comparison: punctuation, spacing, "&"/"and" ignored; author or parenthesised year differences count). Rank stays part of the name Fact.
**Testing:** natural keys with sensu; authorship formatting variants are one Fact; a real difference is two.

### Task 3: Legacy statements at cutover
**Files:** `lib/gallformers/catalog_migration.ex`, new `catalog_migration/legacy_taxonomy.ex`.
**Behavior:** for every non-plant taxon: placement, accepted name (rank, authorship, sensu), each synonym, each common name as undated statements of "Gallformers legacy data". Plants get none. Idempotent; chunked like `legacy_facts.ex`.
**Testing:** migrated test DB holds one current placement and name per non-plant taxon; plants none; re-run changes nothing. Then Task 5's check reports no differences.

### Task 4: Taxa operations the sync needs
**Files:** `lib/gallformers/taxa.ex`, `taxa/events.ex`, `catalog/taxon_listener.ex`, `catalog` (Inducer re-pointing).
**Behavior:** `set_rank/3`, `set_authorship/3`; `add_synonym`/`remove_synonym` emit events; `merge/3` (lump: B's names become A's synonyms, B's `inducer_of` Facts re-pointed to A in place (each keeps its attributions and their `name_as_written`; merged into A's Fact where one exists), with no new attributions; emits `:merge`, Gall renames follow, collisions flagged by the existing flow); `split/3` emits `:split` (daughters exist as taxa). Listener errors roll back as today.
**Testing:** each op audited and emits its event; merge re-points Inducers and proposes renames; a collision fails the merge with the reason.

### Task 5: The tree follows the Facts
**Files:** new `lib/gallformers/taxa/sync.ex`, Facts.Events registration (`config/config.exs`), `lib/mix/tasks/gallformers.taxa.check_sync.ex`.
**Behavior:** on `facts_changed` for taxonomic kinds, `Sync.apply/1` reads each affected slot's winner and rewrites `taxa`/`taxon_names` through Task 4's writers and `Taxa.place/3` (`Tree.validate_parent`), in the same transaction. A cycle or rank inversion fails the transaction with the reason (so an acceptance that would break the tree is refused). `Sync.check/0` rebuilds the expected tree from Facts and lists differing rows; the mix task runs it on demand; a test asserts it's clean after the test DB build.
**Testing:** accept a placement → taxon moves and Gall renames are proposed; retract → moves back; accepted name change → rename event; synonymy accepted → merge; refused acceptance on a cycle; check finds a hand-edited drift.
**Depends on:** 1, 3, 4.

### Task 6: The taxonomy queue
**Files:** queue kind migration (`:taxonomy_acceptance`, package optional); `lib/gallformers/import/apply_taxonomy.ex` (`disagreement/3` raises acceptance items carrying `fact_id`/`attribution_id`); `import/queue.ex` (doesn't hold approval); `lib/gallformers_web/admin/review/questions.ex` and a new queue page beside Gall renames; the Source overview's count and link.
**Behavior:** an item only when the statement is newer than the latest accepted paper for that taxon slot; accepting closes open items from older papers on the same slot as history. Choices: accept (tree follows), decline with a required reason. "Accept the rest of this paper" after a preview of tree effects (moves, renames, Gall names changing, split questions opened); declined acts stay declined. Name-resolution questions (`:synonyms` section) still hold approval; `:acts` become acceptance items.
**Testing:** volume rule both ways; closing older items on accept; bulk accept skips declined; Source approval not held by acceptance items.
**Depends on:** 1, 5.

### Task 7: Split questions
**Files:** queue kind `:split_inducer`; `Catalog` listener on `:split`; `catalog` Inducer re-pointing; questions/page.
**Behavior:** on an accepted split, Galls the splitting paper's own gall statements cover take its Inducer; each other Gall on the split taxon gets one question, "Which taxon induces this Gall now?" (each daughter, or not known yet → stays, marked broad sense on its `inducer_of` Fact). Older attributions untouched (`name_as_written` kept).
**Testing:** covered Gall settles without a question; uncovered gets one; not known keeps the Inducer with the mark; answers trigger renames.
**Depends on:** 4, 6.

### Task 8: Taxonomy admin edits credited to a Source
**Files:** `lib/gallformers_web/live/admin/taxonomy_live/edit.ex`, `new.ex`, `index.ex`; `lib/gallformers/import.ex` (`record_taxonomy_edit` for non-plants writes act statements); `lib/gallformers/sources.ex` (audited, replayed Source creation for a quick citation).
**Behavior:** non-plant moves, renames, synonyms, rank, authorship and common names ask "Based on which Source?" — pick a Source or create a citation (title, authors, date) — and are recorded as that Source's statement, accepted. "No Source: Gallformers' own position" needs a reason. If an accepted newer paper already decides the slot, the edit says so and changes nothing. Plants keep today's direct edits.
**Testing:** an edit credited to a picked Source moves the tree; a later import of that Source's same act raises no item; outranked edit explained; Gallformers fallback requires a reason; plant edits unchanged.
**Depends on:** 1, 5.

### Task 9: Phase 1 carry-over
**Files:** a one-off in the cutover (`catalog_migration` or replay).
**Behavior:** tree-changing synonym decisions (`synonym_decisions.ex` split / synonym_of, stored as `:queue_decision` with `taxon_id`) map to acceptances of the Source's matching act attributions; unmapped ones are reported for a curator.
**Testing:** a phase 1 "change the tree" decision becomes an acceptance and raises no item after cutover.
**Depends on:** 1, 6.

### Task 10: Showing taxonomic Facts
**Files:** `import.ex` `facts_for_source/1` (include `taxon_` kinds), `import/facts_view.ex`, `components/facts_components.ex`, taxon pages.
**Behavior:** a Source's applied taxonomic statements with accepted / declined (reason) / awaiting; a taxon page shows its position's Source and the papers that disagree.
**Testing:** applied Source lists its acts with marks; declined reason shown.

**Order:** 1 → 2 → 3 → 4 → 5 → 6 → (7, 8, 10 in parallel) → 9 before cutover. 50ff step 3; curation (ec2c change set) first.


## Build status (2026-11-06)

Tasks 1–5 built and merged (`55ed22b7`, merge `49a08c51`; precommit 3,817 tests clean). Tasks 6–10 remain (they need screens).

- **Task 1:** columns on `attributions` (`accepted_at`, `accepted_by_user_id`, `declined_at`, `declined_by_user_id`, `decline_reason`; checks: not both, a decline needs a reason); `Facts.accept/3`, `decline/4`, `reopen/2`, `counts?/3`, `needs_acceptance?/2`; `taxon_*` statements count only when accepted or from Gallformers' own Sources; replay kind `taxonomic_decision` (`Import.TaxonomicDecisions`). `Facts.Events` listeners may refuse a write (`{:rejected, listener, reason}`). A Fact whose statements all await or are declined is `:unsupported`. A re-import that changes a statement's stance clears its acceptance; restating it unchanged keeps it.
- **Task 2:** root placements at any rank (today's tree has family-rank roots); `name_facts` gain `sensu`, `authorship`, `normalized_authorship` (`NameNormalizer.normalize_authorship/1`: case, spacing, punctuation, "&"/"and" ignored; authors, year, parentheses count).
- **Task 3:** `CatalogMigration.LegacyTaxonomy` writes today's non-plant tree as undated legacy statements (placement, accepted name with rank/authorship/sensu, synonyms, common names); idempotent.
- **Task 4:** `Taxa.set_rank/3`, `set_authorship/3`, `set_sensu/3`, `merge/3` (`Taxa.Lump`), `split/3`; synonym add/remove emit events. A lump moves B's Galls and their Facts to A with their attributions (`Import.TaxonMerges`), re-points generation groups, proposes renames; B's real-Source statements are declined ("B was merged into A") and kept, Gallformers' removed; B is redirected and deleted. Refused for a B with children, plants, or an open question naming B.
- **Task 5:** `Taxa.Sync` follows slot winners in the same transaction (placement, rank, name, authorship, sensu, synonyms, common names, split events); a cycle, rank inversion or lump of a taxon with children refuses the acceptance. `Sync.check/0`, `mix gallformers.taxa.check_sync`, `Release.check_taxa_sync/0`; a test asserts the built test DB is clean.

**For Tasks 6–10:**
- An open queue item naming B blocks B's lump, so an acceptance item carrying B's taxon id would block its own lump: exempt the item being decided.
- A name statement with authorship and one without are different Facts, so a paper that only adds authorship competes in the slot: don't raise a question for it (accept as compatible, or compare without authorship first).
- Until Tasks 6 and 8, the drift check lists taxa that imports create as new and non-plant taxonomy-admin edits (no current Facts yet).
- A Gallformers-Source taxonomy batch counts without acceptance and moves the tree (consistent with Gallformers' own statements); keep it the rare exception.
- Retracting a lump's paper removes the synonym but leaves B's Galls on A; splitting back is curator work.


- **A revalidated name outranks an older synonymy of it (Jeff, 2026-11-06; option b).** A paper revalidating a name usually states only its name and placement, not "N is not a synonym of X". Rule: once a name is a taxon's accepted name by a dated, accepted statement, an older statement making that name a synonym of another taxon (legacy undated included) stops counting. Recency applied across name and synonymy statements; fixes the carry-over's "synonym missing" differences and the lump hazard (a later sync treating N as lumped into X). A curator who disagrees declines the paper. Rejected (a): relying on curators to record the denial each time.


## Build status: Tasks 6–10 and the revalidated-name rule (2026-11-06/07)

All ten tasks built and merged into taxogall (Task 8 `6b88eda2`, Tasks 9–10 `8955460d`, Task 6 `0a5920da`, revalidated-name rule `49dfc104`, Task 7 `66c846fb`); precommit 4,062 tests clean.

- **Task 6, the taxonomy queue** (`Import.TaxonomyQueue`, `/admin/review/taxonomy`): `:taxonomy_acceptance` items across Sources, never holding approval; raised only for a statement newer than every counting statement in its slot; accepting closes older papers' questions as history; decline needs a reason; "Accept the rest of this paper" previews the tree changes (rolled back) then accepts all not declined. Plants' acts stay phase-1 `:taxonomy_disagreement`. Taxa an import creates have their name and placement statements accepted as created. Papers that agree with the tree raise nothing and stay awaiting. A non-plant's first common name now raises a question.
- **Task 7, split questions** (`Import.SplitQuestions`): on an accepted split of A, Galls the paper places settle on its daughter (older attributions kept as written); each other Gall gets one `:split_inducer` question (each daughter, A in its narrow sense, or not known yet → stays on A marked broad sense, `relationship_facts.broad_sense_split_id`, shown on the Gall page). A shared-Host heuristic suggests a daughter (marked recommended, "a suggestion to check", never bulk-accepted). A split may keep A among its daughters. A retracted or declined split leaves moved Galls where they are (as lumps do).
- **Task 8, "Based on which Source?"** (`Import.TaxonomyStatements`, `record_taxonomy_change/3`, `BasisPicker`): non-plant edits in the taxonomy admin and on the species page are recorded as the chosen Source's statement (existing, a citation made on the spot, or Gallformers' own with a reason) and accepted at once; an outranked edit says so and changes nothing. A re-import keeps a curator's credited statements. Citation creation is logged as a Source edit (the `source` table has no row-level audit). Plants stay editorial.
- **Task 9, carry-over** (`Import.TaxonomyCarryOver`, run by `Release.replay_log/1` after the replay): phase 1 tree-changing decisions and acts a curator followed (among `:taxonomy_disagreement` items, or the `:taxonomy_acceptance` items the replay now raises) become acceptances, dated at cutover with no curator recorded (the log doesn't keep who); unmatched ones are reported. Splits are never auto-accepted.
- **Task 10, showing statements**: a Source's taxonomic statements on its public page and the review Facts page with accepted / declined (who, when, why) / awaiting; `Import.taxonomic_position/1` and the `taxonomic_position` component (used by the species page).
- **Revalidated-name rule**: name and synonymy Facts of one name share a `contest` on the Fact; `Standing.settle_contests/2` supersedes an older synonymy once a dated, accepted name statement claims the name for another taxon; declined or retracted, the synonymy counts again. A later rename of the taxon keeps the outranking (the agent read "once accepted" as "from then on"; a one-line change if Jeff meant "only while it is the current name"). The migration adds contests to existing Facts without recomputing standings: production synonymies that should be superseded change at their next write (or run `Facts.recompute_for_source/2` for the relevant Sources) — before release.
