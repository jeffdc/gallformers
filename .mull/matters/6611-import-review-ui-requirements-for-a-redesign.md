---
status: active
created: 2026-10-30
updated: 2026-11-07
epic: admin
relates: [a856, 20e5, e381, d213, bc0d, c8c3]
---

# Import review UI: requirements for a redesign

# Import review UI: requirements for a redesign

Requirements for redesigning the import review UI (today `/admin/queue` and `/admin/queue/packages/:id`), written so a dedicated design agent can work from this matter alone. Design first, implementation later. Jeff's judgement after using the first version on real data (2026-10-30): **"It is not usable in any real sense. We need to rethink this entire UI."**

## Context

- **What it's for:** Sources (papers, books, web pages, and Gallformers' own notes) are turned into import packages by a producer pipeline. Gallformers resolves each package's names and Galls against its catalog. What it can't settle on its own becomes a **queue item** for a curator. A package is approved when nothing blocks it, and its statements then become Facts.
- **Who uses it:** a curator who knows galls, hosts and taxonomy well, and who reviews one Source at a time. Today that's Jeff, working locally. Later it will be several curators on preview, before the public release.
- **Scale:** the backscan covers about 927 Sources plus about 1,325 Gallformers notes. A large old Source has dozens of items: Ashmead 1896 had 110 open items, 51 after the 2026-10-30 fixes. Most items now come with a proposed answer (82 of 114).
- **Where admin is going:** Jeff expects admin to move away from traditional form-per-record UIs. Pipeline batches are the main way data gets in (`8567` rule 12). This UI is where a curator checks and settles what the pipeline produced.

## Jeff's feedback on the first version (2026-10-30)

1. **The queue is item-first, and that will never make sense.** The page lists every open item of every package at once. The package list sits at the bottom, under hundreds of entries. **It must be driven Source-down:** start from Sources (packages), then drill into one.
2. **Mostly whitespace.** Each item is a tall card: big inputs, an empty note box, buttons. Very few items fit on a screen, and the package page is the same.
3. **Internal codes everywhere.** Refs like `t24`, `t51`, `g1` and `f5` are batch-local identifiers from the producer's JSON, and they mean nothing to a curator. The same goes for terms like `edit_distance`, `held_valid`, `mode add`, batch IDs, and "taxonomy.json — taxonomy batch".
4. **The two pages don't explain how they relate.** The queue page and a package's page show the same data from different angles, and nothing says so. The package page also shows confusing empty states, such as an empty statements table reading "Not resolved yet."
5. **Curators think in names, not IDs.** "Another taxon by ID" is useless. Curators need tools to find and choose taxa, plants and Galls **by name**, including searching the tree, synonyms and WCVP, and adding a synonym or a plant where needed.
6. **Unclear what to do, and what happens if you do nothing.** For an unresolved Host with a suggestion, the only actions offered are "Skip" or "pick another taxon ID". The page doesn't say the suggestion is the likely answer, what each choice does, or what leaving the item does. (Leaving it holds the whole gall batch.)
7. **Gallformers notes:** Jeff expected the notes to be collapsed into groups by category, not shown one by one. Today each note is its own package, a judgement call from 2026-10-30 that is open to change. See *Open questions*.

## Requirements

### Structure: Source-down

- **The landing page lists Sources with work waiting.** For each: title and citation, kind (a paper, a website, Gallformers notes), how many items need a decision, how many have a proposed answer, what blocks approval, and status. Sorted and filtered so the next Source to work on is obvious.
- **One Source's page is where the work happens.** It shows:
  - what the Source states, summarised: how many Galls, Hosts, Traits, taxonomic acts and unmapped terms;
  - what needs a decision, grouped by the kind of question;
  - what's blocking approval;
  - the approve and deny actions.
- **Gallformers notes are one Source with about 1,325 notes,** grouped (by category, undescribed vs described, or batch). They are not 1,325 separate entries on the landing page.
- **A cross-Source view is optional,** for example "every unresolved Host name across Sources", since one decision can clear the same name in several Sources. It is secondary, never the landing page.

### Language: the curator's words

- **No internal refs** (`t24`, `g1`, `f5`), batch IDs, file names, format versions or method codes in the main view. Name things the way the Source does ("ANDRICUS CHRYSOLEPIDIS", "the gall of ANDRICUS MORRISONI") and the way the catalog does (the Gall's name, the taxon's accepted name).
- **Each item states its question in plain words,** for example: "Is 'Quercus imbrecaria' the plant *Quercus imbricaria* Michx.?" or "Which Gall is 'the gall of Andricus morrisoni'? The Source names no generation; Gallformers has only the sexual generation's Gall."
- **Technical detail stays available but tucked away,** for debugging: refs, the raw statements, how a match was made.

### Each decision: clear, name-based, fast

- **Show the proposed answer as the default,** with one action to accept it. 82 of 114 items have one.
- **Give each choice a label that says what it does,** for example "Use *Q. imbricaria* (adds 'imbrecaria' as a synonym)", "Create a new taxon", or "Leave this name out of the import".
- **Say what leaving an item open means:** "Holds approval of this Source's Gall statements", or "Doesn't hold anything; acknowledge when ready".
- **Give enough evidence to decide right there:**
  - the Source's own text: the quote and page;
  - the candidates, with what tells them apart: generation, Hosts, plant part, author, WCVP status;
  - links to the Gall or taxon page.
- **Pick by name.** Use search with autocomplete over the tree (accepted names and synonyms), plants (tree and WCVP), and Galls (name, Inducer, Host). Never a numeric ID box.
- **Name tools in place:** add a synonym, add a plant from WCVP, create a taxon, each from the item itself. The backend needs new decision shapes for the first two (`a856`, open list).
- **A note on a decision is optional,** shown on demand rather than as an empty box on every item.

### Density and speed

- **Many items visible at once,** in a compact row per item that expands for detail. Keyboard-friendly where it helps.
- **Bulk actions for repeated, low-risk answers,** for example "accept all proposed answers in this group, after review". Example: Ashmead's 22 Galls whose 1896 text names no generation, where Gallformers holds only one Gall of each Inducer.
- **Progress per Source:** how many items are decided and how many remain. After a decision, the page updates in place; items that a decision settles go away, and new ones that it calls for appear (`a856`: deciding re-resolves the package).

### The kinds of question (what the design must cover)

| Today's kind | The curator's question | Answers |
|---|---|---|
| Unresolved name / ambiguous match (a taxon) | Which taxon does the Source mean by this name? | a candidate (often proposed); another taxon by name; new taxon; leave it out |
| Unresolved Host | Which plant is this Host name? (holds the Gall statements) | a suggested plant (adds the name as a synonym); a plant added from WCVP; another plant by name; leave it out |
| Taxonomy disagreement (a name) | The Source treats a name as valid that the tree holds as a synonym. Follow the tree, or note it? | follow the tree's taxon; acknowledge; leave it out |
| Taxonomy disagreement (an act) | The Source places or names a taxon differently from the tree. | acknowledge (history only until taxonomy phase 2) |
| Ambiguous Gall / undescribed-Gall candidate | Which Gall entry is this? | a candidate (proposed, with traits to compare); a new Gall; leave it out |
| Generation pair | Two of the Source's Galls (different generations) match one entry with no generation. Which one is it? | pick one; the other is new |
| Dispute | The reviewer and the producer disagree about a statement. | keep it; drop it |
| Same-date conflict | Two Sources of one date disagree. | acknowledge (curator follow-up) |
| Generation outside its group | A generation that doesn't fit the Inducer's group. | acknowledge |
| Source match | Which Source is this package? | a candidate Source; a new Source |
| Gall rename proposal (not from a package) | A taxonomy change implies a new Gall name. | accept; reject |

A Gall that waits on its Inducer's name has no item of its own; the Inducer's item should say how many Galls it decides.

## Out of scope for this design

- **Curator intake of new knowledge** (`20e5`), for example adding a Host from an iNat Observation. It's related, since it also produces packages, and should feel like the same tool, but it's a separate design.
- **Taxonomy phase 2 editing** (splits, lumps).

## Open questions for Jeff and the designer

1. **Gallformers notes:** stay one package per note (so a curator's edit to one note is its own small package), shown grouped under the one Source? Or are notes batched into packages by category (fewer packages, but a curator's later edit can't be its own)?
2. **The Source page's primary layout:** organised around the questions (grouped by kind), or around the Source's own Galls (each Gall with its statements and any questions about it)?
3. **Bulk accept of proposals:** allowed for which kinds, and with what safeguard?
4. **Who approves:** the same curator, or a second person, once there are several curators?


## Working design (2026-10-30)

A clickable design to iterate on: https://claude.ai/code/artifact/8f5d9269-9161-4544-8d34-22080beb141c (private to Jeff). Source file: `docs/plans/review-redesign.html` (local, gitignored); republish it to the same artifact after edits.

- Built on the site's design system (League Spartan; gf-maroon, gf-sky-blue, cadet-blue table heads; the gf-btn, gf-badge, gf-pill and gf-card styles), light and dark. No artifact types or design systems were available to the account, so it is plain HTML.
- Three screens, filled with the local queue's real data: the Sources list; Ashmead 1897's page (questions grouped by kind, a compact row each, Accept for the proposed answer, expandable evidence, choices that say what they do, name search, what leaving it open means, bulk accept with an inline confirmation, a "By Gall" sketch); and the Gallformers ID Notes grouped by what they hold, with the 10 trial notes and the 5194 dispute.
- Each screen has a "Design notes" panel tying it to the feedback above and listing the open questions.


## Decisions (Jeff, 2026-11-01)

- **No cross-Source view.** Each Source is resolved on its own, independently of others.
- **Every section can be accepted in bulk.** A curator rejects the few proposals they disagree with, then accepts the rest at once. Rejected rows, suggestions to check and rows with no proposal stay open.
- **Organise a Source's page by question, not by Gall.** One answer covers every Gall it applies to. Verified: a Host name is declared once per Source and every statement naming it points to that declaration (Ashmead: "Quercus chrysolepis" behind 6 Host statements, "Quercus" behind 10), and a name declared in both the taxonomy and gall batches is queued once (`a856`). Rows that cover several Galls show how many.
- **Traits must be designed, not just taxonomy** (the first mockup was ~95% taxonomy). Version 2 of the design adds:
  - **Disputed Trait values:** both readers' cases and the definitions of the values in play side by side; keep the producer's value, use the checker's, another value from the Trait's list, or drop it. One question can cover several Galls (Floate's two purse-like pseudogalls: leaf curl or pocket?).
  - **Trait terms with no vocabulary value** (today's `unmapped`): proposed "keep as text on the Gall", so the section can be accepted at once; or map to a value (the nearest suggested, with its definition), or request a new vocabulary value.
  - **Statements set aside as hedged or not Facts:** proposed "keep it out"; or state it ("Host: Rosa (genus)" for Ashmead's "rose" on 2 Galls; "hybrid intermediates" on 4 Galls in Floate).
  - These two don't hold approval: left alone, terms stay as text and set-aside statements stay out.

**Open questions added:**
- Should terms set aside hold approval? (designed: no)
- Where do requests for a new vocabulary value go, and who adds the value?
- When a disputed Trait is dropped, is it gone, or kept as text on the Gall?

**Backend implications** (not built): today `unmapped` entries are recorded but take no decision. Mapping a term to a value, stating a set-aside statement, and requesting a new value would each need a decision shape and an applier; per-section bulk accept needs an "accept all proposed" action; "reject a proposal" needs a state that keeps the item open without the proposal.

Design artifact version 2: same link as above.


## Decisions (Jeff, 2026-11-02)

- **Terms and statements set aside never hold approval.**
- **New vocabulary values go to a backlog** that senior admins (the existing `superadmin` role) review: add the value (with a definition), map the term to an existing value, or decline. Each request keeps its origin (Source, Gall, term, quote, batch), so when a value is added or a term mapped, every Gall behind the request gets the Fact, attributed to its Source with its quote.
- **Dropping a disputed Trait value keeps the Source's words as text** on the Gall.
- **A name held under several species** (misapplied or invalid names): a name held twice by the same species already resolves with no question (the resolver dedupes candidates by taxon). Two or more species holding it is a question, shown as a comparison: each species, the names it holds, its Hosts and Gall, against what the Source says.
- **UI:** clicking anywhere on a row opens or closes it, as its button does. "It's another generation's Gall: create it." The notes are built for scanning: a Ready list of notes needing nothing (one line each, ticked by default, what they add as chips), approved in bulk; "Needs you" holds the rest.
- **The mockup is final** (version 3, same link). Next: make it real, replacing today's queue pages.

## Making it real: scope (2026-11-02)

Replaces `/admin/queue` and `/admin/queue/packages/:id` (item-first) with Source-down pages. Three parts:

1. **UI on the existing backend.** Sources list; a Source's page with sections by question, compact rows that expand, plain-language questions and choices, Accept / Reject / bulk accept, approve and its reasons; name search (taxa with synonyms, plants in the tree and WCVP, Galls) reusing existing search components; the notes Source with Ready / Needs you and bulk approve across its packages; technical details tucked away.
2. **Backend for the new decisions.** A rejected-proposal state and per-section bulk accept; Host decisions that add a synonym or add a plant from WCVP; terms set aside and statements set aside as non-blocking queue items (grouped by term within a Source, covering several Galls), with decisions to map to a value or state the Fact (built by the curator with pickers, so no contract change or re-production); Trait-dispute choices (keep, the checker's value, another value, drop to text); grouping disputes that ask the same question across Galls; the comparison data for multi-species names; every new decision in the replay log.
3. **Vocabulary backlog.** A requests table keeping each request's origin, the superadmin screen, and applying an added or mapped value back to the Galls behind it. Blocker: until cutover the Trait vocabulary loads from `priv/import/vocab/traits.json`, so adding a value means either editing that file (and regenerating the vocab files and their version) or moving ownership of the vocabulary to the database now.

**Decisions needed before building:** where new vocabulary values live before cutover (traits.json or the database); whether the old item-first pages go entirely.


## Decisions (Jeff, 2026-11-02, continued)

- **The Trait vocabulary moves to the database now.** It becomes the source of truth; `priv/import/vocab/traits.json` becomes generated output only.
- **The old queue pages stay while the new ones are built, only if that costs little.** If a backend change breaks them, delete them rather than fix them. They go in the last task either way.

## Implementation Plan

**Goal:** replace the item-first review queue with the Source-down review designed in the mockup (version 3), with the backend decisions it needs and a vocabulary owned by the database.

**Architecture:** the backend gains the new decisions, non-blocking items for what producers set aside, and a vocabulary-request backlog, all recorded in the replay log. A presenter module turns each queue item into a section, a plain-language question and labelled choices; new LiveViews render Sources, one Source's sections, the notes Source and the backlog. Tests first throughout (failing test, watch it fail, implement).

**Reuse:** `typeahead` and `search_input` (`form_components.ex`); WCVP search as in `TaxonomyLive.New` (`search_wcvp`, `start_async`); `Import.record_synonym_added/4` and `record_plant_added/2`; `Gallformers.Import.Replay` and `StableRef` for every new decision; the `superadmin` live session for the backlog.

### Task 1: The vocabulary is owned by the database
- `Catalog.Vocab.Loader.load/2` seeds only: it inserts values and term mappings that are missing and never overwrites one (a definition edited in the database stays). The catalog migration still calls it, so a fresh database starts from the committed file.
- New `Catalog` functions to add a Trait value (with its definition, required) and to add a term mapping, audited; each appends a replay entry (new kinds `trait_value_added`, `term_mapping_added`) so values added on preview replay at cutover.
- `mix gallformers.import.vocab` keeps writing the contract files from the database; a value added there appears in `traits.json` and `traits.schema.json` once regenerated and committed. Update the Loader and `Import.Vocab` moduledocs and `priv/import/README.md` (no longer "edit traits.json").
- Tests: reloading doesn't overwrite an edited definition; an added value is in the generated files; both replay entries replay.

### Task 2: Non-blocking items for what producers set aside
- Resolving a batch turns its `unmapped` entries into queue items of two new kinds: `:set_aside_term` (slot is a Trait) and `:set_aside_statement` (hedges, places, relationships, not-a-Host, other). Never blocking (`Queue.blocking?/2`).
- One item per term within a package (normalized term + slot); `subject["covers"]` lists the Galls (refs and names) and quotes, so one answer covers them all.
- Proposal: keep (as text / out). Decisions: keep; map to a Trait value (`%{"trait_value" => v}`); state it (`%{"state" => …}`, built by the curator with pickers: a Trait value, a Host by name, a place); request a new value (`%{"request_value" => true}`, Task 4). Mapped and stated decisions write the Fact on apply, attributed to the Source with the unmapped entry's quote as evidence.
- Tests per decision, including one answer covering several Galls, and apply writing the Facts.

### Task 3: The other new decisions
- **Reject a proposal:** `Import.reject_proposal/2` keeps the item open and marks its proposal rejected (excluded from bulk accept; shown as rejected).
- **Accept all proposed:** `Import.accept_proposals/2` decides a list of items with their proposals in one transaction, each logged for replay; skips rejected, weak (suggestion only) and proposal-less items.
- **Host decisions:** use a plant and add the Source's spelling as its synonym (`%{"taxon_id" => id, "add_synonym" => true}`); add the plant from WCVP (`%{"wcvp_id" => id}`). Both through the existing synonym and plant recorders, so they replay.
- **Trait disputes:** keep; use another value (`%{"value" => v}`, the checker's or any of the Trait's); drop, which turns the statement into a set-aside term (text on the Gall), not nothing.
- **One question across Galls:** disputes with the same Trait, value and suggested value are one item (`subject["also"]`), as names already are.
- **Names held by several species:** a read-model function gives each candidate's accepted name, the names it holds, its Galls and their Hosts, for the comparison.
- Tests for each, and replay for each new decision shape.

### Task 4: Vocabulary requests
- New table `vocab_requests`: trait, term, the package, batch and unmapped entry it came from, the Gall (ref, and ID once applied), quote, status (requested, added, mapped, declined), who decided and when, the value it ended as.
- A `request_value` decision (Task 2) creates one. Superadmin actions: add the value (Task 1, definition required), map to an existing value, decline. Added or mapped: every request behind the term gets its Trait Fact, attributed to its Source with its quote; a request whose batch isn't applied yet gets it when the batch applies. Declined: stays as text.
- Requests for the same Trait and term are gathered. Replay entries for each action.
- LiveView `/admin/vocab-requests` in the `superadmin` live session.

### Task 5: The questions, in the curator's words
- New module (e.g. `GallformersWeb.Admin.Review.Questions`): from an item (kind, method, flags, subject, proposal) gives its section, the question in plain words, the proposed answer, labelled choices with what each does, whether it holds approval and what leaving it open means, and how many Galls it covers. No refs or method codes; those go to a technical-details string.
- Sections as in the mockup: Host names; names called new that Gallformers holds; names held by several species; names now treated as synonyms; Galls whose generation isn't named; disputed statements; disputed Trait values; Trait terms set aside; statements set aside; plus Source match, generation pairs, undescribed Galls, same-date conflicts, generations outside their group.
- Unit tests per kind (the copy is part of the contract with the curator).

### Task 6: Sources and one Source's page
- `/admin/review`: Sources with work waiting (packages grouped by Source; the notes' packages under the one Gallformers Source), with counts, how many have a proposal, what holds approval, and filters and sorting.
- `/admin/review/sources/:id`: the Source summary, progress, approve with its reasons, deny; sections of compact rows that open on a click anywhere on the row; Accept, Reject, Accept all proposed with an inline confirmation; choices with name search (taxa with synonyms, plants in the tree and WCVP, Galls) through `typeahead`; Trait values with their definitions; the comparison for names held by several species; an optional note; technical details tucked away. Updates in place after each decision (deciding re-resolves the package).
- LiveView tests for each behaviour.

### Task 7: The Gallformers notes
- The Gallformers Source's page groups its note packages by what the note holds (undescribed Galls; Hosts and sightings from Observations; other), computed from the Gall and the note.
- "Ready, nothing to decide" lists notes with no open blocking items, one line each with what they add as chips, ticked by default; "Approve N ticked" approves those packages at once (`Import.approve_packages/2`). "Needs you" lists the rest, opening in place.
- Tests: ready vs needing; bulk approve approves only the ticked.

### Task 8: Retire the old pages
- Delete `QueueLive.Index`, `QueueLive.Package`, `ItemDecision`, their components and tests; redirect `/admin/queue` and `/admin/queue/packages/:id` to the new pages; update the admin navigation and `a856`.

**Order:** 1 → 2 → 3 → 4 (backend), 5 alongside, then 6 → 7 → 8. **Size:** about 4–7 working sessions with agents, Jeff's review being the pace.


## Status: built (2026-11-02, uncommitted)

All eight tasks are built; `mix precommit` passes (2,764 tests). The local review database (`gallformers_taxogall`, 127.0.0.1:54317) is migrated and its packages resolved again; every package's page and the notes page load on the real data.

- **Pages:** `/admin/review` (Sources; Gall rename proposals as their own row when open), `/admin/review/sources/:id` and `/admin/review/packages/:package_id` (a new Source has no Source row until applied, so it opens by package), `/admin/review/renames`, `/admin/vocab-requests` (superadmin). `/admin/queue…` redirects. Nav: "Review", and "Vocabulary" for superadmins.
- **Code:** `lib/gallformers_web/live/admin/review_live/` (`loader`, `sources`, `source`, `item_row`, `notes`, `renames`), `lib/gallformers_web/admin/review/` (presenter `Questions`), `lib/gallformers_web/components/review_components.ex`, `VocabRequestsLive`; backend `Import.SetAside`, `Import.Proposals`, `Import.HostDecisions`, `Import.Disputes`, `Import.VocabRequests`, `Import.VocabEdits`. Old `QueueLive` deleted.
- **On the local data:** Ashmead 51 questions (41 with a proposal) and 19 set aside; Osten Sacken 28; Floate 12 (its two purse-like pseudogall disputes are one question); Nastasi & Davis 16; Aphis rubifolii 6; notes: 9 ready, 1 to decide.

**Open:**
- Mapping a requested term to a value doesn't add a term mapping, so producers won't map that term on their own next time. Add one on map (and on add)?
- The notes page makes about two queries per note; it needs batching or paging before all ~1,325 notes are packaged.
- The Sources list's progress bar shows only the proposal share (decided counts per package would need a count query).


**Host rows fixed (2026-11-02, Jeff's review of Aphis rubifolii):** each section now heads its columns "The Source wrote" → "Gallformers proposes". A variety's species is only ever a suggestion, never the firm proposal, and comes after a WCVP record for the variety itself (Rubus ursinus var. loganobaccus had been proposed as R. ursinus; WCVP sinks it into Rubus × loganobaccus, the loganberry). A suggested plant Gallformers doesn't hold says "Not in Gallformers yet: accepting adds it from WCVP". Side effect: varieties whose species was firmly proposed before (Ashmead's Q. chrysolepis var. vaccinifolia) are now suggestions to accept one by one.


## Redesign, round two (Jeff and Claude, 2026-11-07)

Mockup: `dev/gallformers_web/dev/mockups/source_reading_live.ex`, `/dev/mockups/source-reading/:package_id` (package 97, Nastasi & Davis 2022), on the real questions (`ReviewLive.SourcePage.load/1`, the Traits step's context for trait terms) and the real reading (`Import.preview_package/2`). Deciding is mocked.

**The critique of the built pages:** organised around the pipeline's stages, not the curator's question ("did we read this Source right?"); the Facts, the result, an optional last tab; about 380px of chrome before the first question and the step named three times; deciding takes three clicks (open, pick, Decide) and an open item is ~750px; five phrasings for a recommendation; Hedges is 80 identical decisions; the Sources list's "Holding approval" column is a wall of section names. (Also: the admin sidebar's background stops after the first screen.)

**Direction (Jeff: "directionally better"):** one view of the Source's review, questions in pipeline order, the reading (its Facts by Gall) as context. But all of it at once is overwhelming (Adam's first fear: walls of things to do; small type adds to it). So the default is **one thing at a time**:
- One unit of work at a time, in the admin shell at the **Reading sizes** (proposed `gf-density-reading` class in `tokens.css`, marked PROPOSED, uncommitted). "See everything at once" keeps the full list.
- **One honest count, the same everywhere:** "N of M questions settled. K left, H of them hold approval." Set-aside statements are counted apart ("80 hedged statements were set aside: they stay out unless you state one"). The earlier counts mixed set-aside items into the total and split "need you / to confirm", which read as contradictory.
- Stages as a quiet line (Names · Galls · Disputes · Traits: done ticked, current dotted). "Up next" shows three. "Skip for now" on every unit.
- **"This decides" first** on each card (the Galls and which of their Facts the answer settles), then the question, the Source's quotes, the answers (each with its own button).
- **Batches:** a group's firm proposals as one card, "Accept all N". An item can be set to "Decide on its own" and stays visible in the batch ("you'll decide this one next", Undo); the earlier "Not this one" made items vanish. **Never batched:** "create a new Gall" and a Trait term's "it depends on the Gall" (not an answer until each Gall has its value; batching it is what made the Traits step opaque).
- **A Host nothing matches: three answers, in order:** Search…, Add a new plant… (the New taxon page, prefilled, new tab), Leave this Host out.
- **A Trait term used in several senses is one card listing every Gall it covers:** each Gall's name, the Source's sentence, the candidate values as buttons with the readers' choice picked, "What the readers said" folded away, the values' definitions once at the top, "Settle these N Galls". The curator always sees which Gall they are on.

**Finding: undescribed Galls are mis-proposed as new.** The resolver proposes "Create it as a new Gall" firmly for Galls Gallformers holds: "Toothed rosinweed cryptic stem gall (Antistrophus sp.)" is *Antistrophus s-dentatum-cryptic-stem-gall* (toothed rosinweed is Silphium dentatum; the Source's text says "(S. dentatum)"); "Horkelia stem gall" is likely *Diastrophus p-congesta-stem-gall* (Horkelia congesta, formerly Potentilla congesta; its Host question is open too); "Southern dewberry stem gall" sits beside *Diastrophus r-trivialis-root-gall* (Rubus trivialis). The Source names Galls by the Host's common name; undescribed Galls are coded by the Host's epithet. Accepting such a batch would create duplicates.
- To fix in the matcher: match undescribed Galls on Inducer genus + resolved Host (re-match after Host questions are answered); never propose "create new" firmly while a Gall of that genus on that Host exists.
- In the UI (mocked): the genus's undescribed Galls as quick picks, "Is it one Gallformers already holds?", the one whose Host epithet the Source's text names first and marked ("Its Host, S. dentatum, is the one the Source names"); "Create it as a new Gall" demoted to Check below them.

**Still open:** the reading's place (as context on each card now; Jeff to judge whether "here's what approving writes" should be the last step before Approve); keyboard; the dispute comparison drawn in the card; how the notes Source and the Sources list take this shape.


**Round three (Jeff, 2026-11-07):** the status moves to a rail on the right (sticky on wide screens; below the card on phones): the Source's title, "N of M settled" with a progress bar, "K left, H hold approval", the stages as a vertical list each with what's left ("Names · 4 left", "Disputes · done"), the set-aside line, Up next, Approve and "See everything at once". The card takes the main column's width. **The stages are navigation:** shown in order, but any stage can be chosen to work through next (its units first; skipped units still go to the end).


**Round four (Jeff, 2026-11-07):**
- **Wording, plainly.** Jeff found the copy stiff and "LLM-written" ("Decide on its own", "Approve opens when nothing holds it"). Rewritten as people say it: "0 of 46 answered", "46 to go. 25 of them must be answered before you can approve", "You can approve once the 25 marked questions are answered", "Affects" (was "This decides"), "Suggested" / "Best guess" (were "Proposed" / "Check"), "Is it one of these Galls we already have?", "Why the AI chose this", "Save these 3". The batch card uses checkboxes: "We have suggested answers for these 9. They look right to us. Untick any you want to check yourself; you'll see those next, one at a time." → "Accept all 9" / "Accept the 8 ticked". Each batch row names its trait ("texture: lumpy → Keep as text").
- **One switch between the views,** "One at a time | Everything" (`segmented_switch`), at the top of both.
- **The hedged statements are reachable from the rail:** "80 hedged statements were left out. Review them" opens them in the main column, grouped, each with "Add it…", and "Back to the questions".
- **Headings in cards wrap normally** (`text-wrap`): the base stylesheet's `text-wrap: balance` split long questions into two short lines with a gap, and `text-pretty` isn't supported in Firefox, so it doesn't override it.


**Round five: Trait terms (Jeff, 2026-11-07):**
- **Any valid value, and several of them.** Most Traits take more than one value per Gall ("on the leaf or petiole, occasionally on the stem" is leaf, petiole and stem), and the curator can choose any of the Trait's values, not only those the pipeline mentioned. The per-Gall data already allows a set.
- **The card, per Gall:** the Gall's name and the Source's sentence; one plain line on what the pipeline made of it ("The import pipeline couldn't agree how to map “lumpy” to a texture value." / "…suggests keeping the words as text." / "…suggests: leafy."), with "What each AI said" folded away; then **two choices**: "Keep “lumpy” as text" (the Gall shows the Source's words; the ID tool can't filter on them) or "Map it to texture values", which opens every value of the Trait as a checkbox, the pipeline's suggestions first and marked. With no consensus neither is chosen and Save waits until each Gall has one.
- **The counts say how a batch fits its stage:** "9 of the 21 Traits questions have suggested answers… After these, the other 12 come up one at a time, along with any you untick."
- **Found:** the same words can be asked twice: as a Trait term ("what does “on the leaf or petiole” mean?") and as a dispute about the same statement ("Should “on the leaf or petiole” go in as Ground-ivy gall's plant part?"). The build should ask once.
- **LiveView note for the build:** a checkbox's click sends its own `value` ("on") as `value`, overriding `phx-value-value`; name the parameter something else.

- **Trait disputes use the same card** (Jeff: "the very next one is the old style"). A dispute where the pipeline's AIs disagreed about one Gall's Trait ("single-chambered or have many chambers" for the Lettuce node gall's cells) is the same decision as a Trait term for one Gall: "The import pipeline's AIs disagreed about whether “…” is a cells value", then Keep as text or Map it to cells values (any of them; here monothalamous and polythalamous). Nothing preselected. The old "Keep it / Drop it" wording ("the Gall gets the cells value “…” is placed under") goes.

- **A dispute must say what each side chose, as data.** Nastasi & Davis's "fleshy" (Cinquefoil bud gall's texture): the producer's one-line summary ("The vocabulary's texture value for 'fleshy' is defined by juicy walls…") reads as if "fleshy" were a value; its full reasoning says it mapped "fleshy" to the existing value **succulent** (an existing term mapping). The card now says "The producer mapped “fleshy” to succulent. A checker disagreed: …" and marks succulent as suggested; the mockup reads the value out of the producer's reasoning, the build should carry the producer's (and each checker's) value in the dispute item.
- **Vocabulary question for Jeff:** the checker's rule "texture is the surface" conflicts with our own *succulent* ("The walls of the gall (when fresh) are juicy if cut"), an interior property. Is texture surface-only, and does succulent belong under walls?

- **"X or Y" Trait terms are asked needlessly (pipeline rule, 2026-11-07).** `priv/import/PRODUCER_GUIDE.md` (line ~199) and `VERIFY_GUIDE.md` (line ~37): "Never guess between values. A term that offers a choice or leaves it open names none of them… one Fact with category `null`". So "Green or yellowish" and "single-chambered or have many chambers" become null, a checker objects (two colours), and the curator is asked to tick green and yellow by hand. In Gallformers several values for a Trait already mean the Gall can be any of them, so a term naming alternatives the Gall varies between names each of them (one Fact per value); `null` fits only wording that leaves the value open or that the Source says is unknown. Proposed guide change awaits Jeff. Meanwhile the review card should pre-tick each side's values on a dispute, and a curator's mapping of a term should become a term mapping so no Source asks again (the open item above).


**Next (Jeff, 2026-11-07):** work through `c8c3` first (its Gallformers-side fixes, then the guide change once worded), then return to this design with re-resolved data (Nastasi & Davis, package 97) and keep pushing the UI.

