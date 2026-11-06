---
status: planned
created: 2026-11-02
updated: 2026-11-05
epic: gall-traits
relates: [eb47, e381, 294c, 6611]
---

# Trait vocabulary: categories with Source sub-terms

## Problem

Sources describe galls in unconstrained language. Gallformers' trait vocabulary is small and controlled because the ID tool filters on it. Letting each Source bring its own values would make the ID tool's lists unusable. A strict, expanded ontology (GallOnt, Prior Lab protocols; see `eb47`) has failed to be adopted in practice and would hurt the ID tool too. The ID tool has worked on the current vocabulary for six years.

Today the producer must choose a controlled value for every trait term. In 19 producer packages (2026-11-02), 90% of 943 trait Facts were mapped from other wording, with inconsistent results. "rounded" became globular 7 times and was set aside 4 times; "ovoid" was set aside 3 times though globular's definition includes ovate. Some fits were forced: "rough" → mealy, "smooth" → hairless.

## Decision (Jeff, with Adam's input, 2026-11-02)

- **Categories:** today's trait values are the categories. They're the only thing the ID tool filters on. The top level isn't reshaped now.
- **Sub-terms:** the Source's own terms, carried over by the producer, are stored as structured, queryable data. Each sub-term is placed under one category, several, or none yet. Sub-terms can be added freely; their sprawl ("oval", "ovoid", "ovate") isn't policed.
- **Placement:** placing a term puts it under a category for every Source, not just the current one. A term is placed only when that can be done with confidence. Anything else waits for a curator's review and approval. Gallformers publishes in a partial state, never in a known-wrong state: a Gall shows without a category it's still waiting on, never with a wrong one.
- **"Confident" means** the term is already in the table (seeded or ruled before), or the producer and the checker place it in the same category independently. Disagreement, or either reader saying nothing fits, sends it to a curator.
- **States of a Source's term:** placed; pending (stored on the Gall, shown on its page, not in the ID tool, never blocking approval, as `6611` already decided for set-aside terms); placed by a curator (the category Fact then appears on every Gall waiting on that term).
- **Facts are on the category:** sub-terms live on each Source's attribution, so "ovoid" from one Source and "oval" from another both support a single globular Fact, and agreement, denial and standing work as now. Moving a term to another category moves attributions between Facts; this should be rare.
- **Gall pages** show mapped sub-terms, e.g. "Shape: globular (ovoid, oval)".
- **Curator effort:** curators decide only the ambiguous placements. A new category is a rare decision, made when unplaced terms pile up (e.g. a plain "swelling" was set aside ~10 times in the packages above).
- **Sampled review:** a sample of placements made by agreement goes to review, since two LLM readers can share a blind spot.
- **ID tool search** uses sub-terms: a user's "oval" finds globular. Sub-terms stay out of the filter lists.

## Why

It keeps the ID tool usable and keeps the Sources' richness as data. Mapping moves from an LLM judging each Fact to a ruling made once per term. It also keeps open a future natural-language query that reads Source phrasing, which Adam noted is the only version worth building (not a priority).

## Consequences and follow-up work

- **Import contract (`e381`, `294c`):** `controlled_value` and producer guide rule 5 change from "value + `as_written`" to "term per trait, verbatim, plus a suggested category". The producer extracts the term, not the whole sentence; the sentence stays in the quote.
- **Checker:** for a new term, the checker places it without seeing the producer's suggestion (today it checks the producer's value against its definition).
- **Storage:** `trait_term_mappings` becomes the sub-term table, allowing zero categories. Trait attributions gain a structured sub-term.
- **Seeding:** a curator reviews the ~850 existing (Source wording, value) pairs from producer output before go-live, so early Sources don't flood the queue.
- **Review queue (`6611`):** pending terms are queued once per term, not once per Gall. A list of recent agreement-based placements, sorted by how many Galls each affects, supports spot checks; the sampled review draws from it.
- **Open:** whether some current values (pubescent and woolly under hairy, sphere under globular) later become sub-terms, decided from usage.


## Decisions (Jeff, 2026-11-02, continued)

- **One category per term.** A term is placed under at most one category. The existing leaf rule ("on the leaf", no side stated → upper leaf and lower leaf) is the only term that maps to two; no others. This narrows "one category, several, or none yet" above.
- **Categories change rarely, and only by superadmins.** Adding terms is automatic.
- **Curators see only ambiguous placements.** A term used in more than one sense across Sources (e.g. "swelling": abrupt, tapered or stem club, depending on the gall) never maps automatically: mapping it once would put overlapping terms under different categories. The LLM extraction guidance must say so: extract the Source's term, suggest the category from the whole description, and flag a term whose category depends on the gall.
- **Committing waits** until this is incorporated.

## How placement then works (proposed, 2026-11-02)

- **An unambiguous term** (in the table with one category, or new and placed in the same category by the producer and the checker independently) is placed automatically, once, for every Source; later uses map with no decision. A sample of agreement placements goes to spot-check review.
- **An ambiguous term** has no category in the table (it is marked ambiguous, with its candidate categories). Each use is decided from its own context: when the producer and checker agree for that gall, the Fact is written; otherwise it is a question about that Gall on that Source's page, decided per Gall. This keeps "each Source on its own" (6611): there is no global page of terms for curators.
- **A term becomes ambiguous** when its uses are placed in different categories (by readers or curators); it is then never mapped automatically again, and its earlier automatic placements are listed for a superadmin.
- **Superadmins** keep a small vocabulary page: change a term's category (moving its attributions; rare), mark a term ambiguous or unambiguous, and add a category when terms that fit nothing pile up (replaces 6611's vocabulary-request backlog: a request becomes "this term fits no category").

## Changes to what 6611 built (uncommitted)

- Per-Source "Trait terms set aside" items (Task 2) become: automatic placements (no item); per-Gall questions for ambiguous terms and for readers' disagreements (on the Source's page, holding nothing, as set-aside terms do now); terms fitting no category (to the superadmin page).
- Trait-value disputes (Task 3) mostly disappear: a disagreement on a Trait is one of those per-Gall questions.
- The vocabulary-request backlog (Task 4) becomes the superadmin vocabulary page.
- Storage: `trait_term_mappings` becomes the term table (one term per row, one category or ambiguous with candidates, how it was placed and when); trait attributions carry their term; a term waiting on a question is stored on the Gall without a Fact (shown on its page, not in the ID tool).
- Also: the Gall page shows "Shape: globular (ovoid, oval)"; ID tool search matches terms; the seeding screen for the ~850 existing pairs; the contract, producer and checker changes (paid re-production of the trial Sources).


## Decision (Jeff, 2026-11-02)

- **A question about a term is settled on the Source's review page,** by a curator: an ambiguous term's use, a disagreement between the readers, or a new term the readers didn't agree on. It holds nothing (the Gall shows the term without a category until settled).

## Implementation Plan

**Goal:** Trait Facts on categories, with the Source's terms kept as data; unambiguous terms placed once and automatically; only ambiguous uses and disagreements reach a curator, on the Source's page.

**Contract shape (format v4):** a trait Fact carries `term` (the Source's term, verbatim and short; the sentence stays in the quote), `category` (`{"value": v}`, the producer's suggestion, or null when none fits) and optional `depends_on_gall: true` (the term's category depends on this gall). The checker places every trait term blind in `review.json` (`placements`: per Fact, its category or null and `depends_on_gall`), from a copy of the batch with the producer's categories removed. Gallformers keeps reading v3 packages (`value.as_written` as the term, `value.value` as the suggestion, no checker placement).

### Task A: Terms storage
- `trait_term_mappings` becomes the term table: one term per row (`trait`, `term`, normalized key), `category` (one value; the seeded leaf rule is the only two-category term), `status` (`placed`, `ambiguous` with `candidates`, `no_fit`), `placed_by` (`seed`, `agreement`, `curator`, `superadmin`), `placed_at`, `spot_checked_at`. Split today's multi-term rows. Loader and vocab generator follow (the contract's `traits.json` lists terms one per row).
- Trait attributions carry their `term`.
- Terms waiting on a question are stored on the Gall without a Fact (Gall, Source, batch, trait, term, quote, state), shown on the Gall page, not in the ID tool.
- Replay entries for every term change.

### Task B: Contract, producer and checker (format v4)
- Schemas, `PRODUCER_GUIDE.md` rule 5 and Traits, `VERIFY_GUIDE.md` (blind placement), `GALLFORMERS_STATEMENTS.md`, examples, `validate.py` and the Elixir validator, the readiness gate (placements cover every trait Fact).
- The producer's prompts; phase 5 stages a copy with categories removed; the golden scorer reads terms.
- No paid runs without Jeff's go.

### Task C: Placement on import
- For each trait Fact: a placed term → the Fact on its category (the producer suggesting another category is noted for spot check); an ambiguous term → the Fact when producer and checker agree for this gall, else a question; a new term → placed for every Source when producer and checker agree and neither flags it as depending on the gall (`placed_by: agreement`), else a question; `no_fit` → kept as text, counted for superadmins. v3 packages (no checker): only placed terms map; the rest are questions.
- Producers' set-aside Trait terms (`unmapped` with a Trait slot) are new terms with no suggestion → questions.
- Questions: one item per term per package, covering its Galls (`:trait_term`, holds nothing). Decisions: place the term under a category for every Source; use a category for these Galls only (marks the term ambiguous); fits no category (to superadmins); keep as text. Deciding writes the Facts (now, or when the batch applies) and settles the waiting terms; placing for every Source also settles other Sources' waiting uses.
- Replaces `:set_aside_term` and Trait-value disputes (a checker finding on a Trait value becomes a disagreement).

### Task D: Review UI
- The Source page's "Trait terms to settle" section (presenter copy, choices, definitions of the candidate categories, covers); remove the trait-dispute and set-aside-term sections.
- Superadmin vocabulary page (replaces vocabulary requests): terms by Trait with status and Gall counts; move a term (moves attributions); mark ambiguous or not; add a category; terms that fit nothing, by count; recent agreement placements by Galls affected, for spot checks.

### Task E: Gall page and ID tool
- "Shape: globular (ovoid, oval)"; waiting terms shown without a category. ID tool search matches terms (filters unchanged).

### Task F: Seeding
- A task that gathers the (Source wording, value) pairs from producer output, and a superadmin screen to accept, reassign, mark ambiguous or no-fit them in bulk, before go-live.

**Order:** A and B in parallel → C → D and E in parallel → F.


## Status: built (2026-11-02, uncommitted)

Tasks A–F are built; `mix precommit` passes (2,901 tests). The local review database is migrated (the term table: 27 placed, 1 ambiguous; vocabulary files match).

- **Storage (A):** `trait_term_mappings` is one term per row (status placed | ambiguous | no_fit, categories, candidates, placed_by, spot check); attributions carry `term`; `pending_trait_terms` holds a Source's term on a Gall with no Fact yet, settled under a category, as text because the term fits no category (`no_fit`), or as text because a curator kept it so (`kept`). Every term change replays (`:trait_term_edit`).
- **Contract v4 (B):** a trait Fact is `trait` + `term` (verbatim) + `category` (suggestion or null) + optional `depends_on_gall`; the checker places every term blind (`review.json` `placements`, from a copy with categories removed); `unmapped` takes no Trait slot. v3 packages still validate and import.
- **Placement (C):** placed term → Fact; a term that is a category's own name counts as placed; ambiguous → Fact when the readers agree for that Gall; new → placed for every Source by agreement, or no_fit by agreement on null, else a question; v3 new terms are questions. Questions (`:trait_term`) are one per term per package, holding nothing, decided: place for every Source, a category for these Galls, per Gall (`categories`), fits no category, keep as text.
- **UI (D):** "Trait terms to settle" on a Source's page (per Gall: the quote, what each reader said, a category select); superadmin `/admin/vocabulary` (spot checks, terms fitting no category, add a category, move a term with its Facts, mark ambiguous). The vocabulary-request backlog and the Trait-value dispute section are gone.
- **Gall page and ID tool (E):** "Shape: globular (oval, ovoid)"; waiting and text terms shown as text; the ID tool's filter box finds Galls by terms; retracted Sources' terms are left out.
- **Seeding (F):** `mix gallformers.import.term_candidates <dirs>` gathers producer terms into `trait_term_candidates`; "Seed terms" on `/admin/vocabulary` places, marks ambiguous or no-fit, singly or in bulk where uses agree.
- **Decided 2026-11-02:** placing a term that fit no category turns its no-fit text uses into Facts; a use a curator chose to keep as text stays text. (A curator can't place a no-fit term: marking it no-fit closes the other Sources' questions about it; only a superadmin places it later.)

**Open / follow-ups:** the v2 API doesn't expose terms (an API contract change); site-wide search still searches names only; `pending_trait_terms` is listed public in database snapshots (its terms show on Gall pages; it also holds package and queue ids — check); the old `vocab_requests` table stays, unused.


## Format 4 re-run (2026-11-02, local review DB only)

Re-ran the five golden Sources and the 10 trial notes with the format 4 prompts. All valid and ready. Cost $39.49 (Sources $32.44, notes $7.05). Delivered as local packages 16–20 (Sources, keys `<dir>-v4`) and 21–30 (notes); old packages 1–15 denied as "superseded by the format 4 re-run".

Golden set: 163 of 177 scoreable items present. Possible regressions to look at: Ashmead f260 (season Fall); Osten Sacken f87 (cells), f127 (oak apple); Floate f51 (season Summer), f110 (description 0.56), f115 (leaf edge fold); Nastasi & Davis f233 (cells), g30 rosinweed cryptic leaf Gall (f265, f266, f269); Aphis f2 (Rubus host_of), f15 (wrinkly).

Settled (Jeff, 2026-11-03): an unnamed "oak" is Quercus, so the producer reading stands. A genus Host is rarely what a curator will accept, but that is the curator's call on each dispute, not a guidance change.


## Decision: "leaf" becomes a real plant part value (Jeff, 2026-11-03)

- Add `leaf` as a plant part value: on the leaf, with no more precise place stated, or not consistently placed. The leaf values (upper leaf, lower leaf, leaf edge, leaf midrib, on leaf veins, between leaf veins, at leaf vein angles) are more precise forms of it. Petiole stays separate, outside leaf.
- Matching: `leaf` contains the leaf values. A search for `lower leaf` matches a Gall recorded only as `leaf`, and a search for `leaf` matches every leaf value. This replaces the ID page's synthetic "leaf (anywhere)". It is an exception that fits the domain, and it is a different concept from d213's term → category placement: values containing values, not Source words under a value.
- The leaf rule (no side stated → upper leaf + lower leaf) goes away. Such a term is placed under `leaf`, so every term has exactly one category, with no exceptions, and the review UI needs only a single choice.
- "Both sides" is literally upper leaf + lower leaf; no "both" value.
- Existing data stays as it is (the 277 upper + lower Galls and the rest); importing Sources will settle it over time.

- Containment is built in for `leaf` only, not an editable "broader value" link (Jeff, 2026-11-03).
- Gall page: a `leaf` Fact and a `lower leaf` Fact from different Sources both show, each credited to its Source; they are compatible, not a dispute.
- Producer and checker guides: "the most precise location the Source supports; `leaf` when it supports no more", replacing the two-Fact leaf rule.

- Terms that name several values (Jeff, 2026-11-03): a term goes under one category, or under each value its words name when they name several ("protruding from both sides" → upper leaf + lower leaf; "green-yellow" → green + yellow). Guessing between values is never placement: an "or" or an unstated side is `leaf`, otherwise the term is decided Gall by Gall. This replaces "one category per term". Multiple values per Gall are common (a Gall can be red, green, or both at once).
- `leaf` is implicit: any Gall with a leaf value implicitly has `leaf`. The ID page treats it so; `leaf` is never stored alongside, or added for, a more precise leaf value. It is stored only when the Source supports nothing more precise.


## Trait term screen redesign (Jeff, 2026-11-03)

The current term question is unusable: four radios and two dropdowns that belong to different radios, with nothing tying them together, and "Add a note" beside "Decide". Redesign the term screen first; carry what we learn to the other question kinds (Hosts, names, disputes) only once terms are settled.

Principles (apply to every decision screen):
- The options are the decision, front and center, each with a one-line summary of what it does.
- A recommended option is labelled: the one most readers chose, with the count ("2 of 3 readers"). With no majority, nothing is recommended.
- Extra input appears only after the option that needs it is selected.
- Details (what each reader said, technical refs) go behind a disclosure at the bottom.
- The note is always shown, with placeholder text, and saved on its own ("Save note"), decided or not, for the next curator. It is not part of the decision and never sits with Decide.

Layout, a new term: the question ("What color is 'yellowish brown'? Your answer applies to every Source that writes it."), then options: each category a reader chose (with its definition and reader count); Another <trait>… (search over values with definitions); More than one <trait> (checkboxes, readers' choices first); It depends on the Gall (a row per Gall with its quote and its own choice); Fits no <trait> (to superadmins); Keep as text. A term with several senses opens with the per-Gall rows, the candidate categories defined once above them.

- Click-through mockup (Nastasi & Davis 2022 terms): https://claude.ai/code/artifact/8d270e3d-fc14-4e85-a3a3-c31ed4d5f1e3 (local file `docs/plans/term-questions.html`, gitignored).
- Settled: producer silence gives way when both checkers agree (see below).

- Mockup v2 (Jeff's feedback): readers are named ("Chosen by the producer and checker 1"), and the section explains once who they are (the producer, and two checker AI models that each place the term blind); rows show a chevron that turns when open; the section says an open term leaves its Galls with the Source's words and no value, so ID can't find them by it, and that the Source can be approved with terms open; the question says the answer sets what the words mean: the Galls here get the value now, later Sources that write them get it automatically, and Galls described in other words don't change.

- Producer silence (Jeff, 2026-11-03): when the producer suggests no category and both checkers place the term under the same value, the checkers' answer stands and the term is placed by agreement, without a question ("round" → globular in Osten Sacken). When all three say no category, it is marked as fitting none by agreement (already so). A real two-to-one split, where a reader names a different value (producer and checker 1 monothalamous, checker 2 polythalamous on "each with a single insect"), stays a question with the majority shown as Recommended: there the minority was right.


## Navigation within a Source (Jeff, 2026-11-03)

A Source's work is split into pages, one per step, in a fixed order, with a nav bar on every page to jump around:
1. Names (which organisms the Source means): Host names, names called new, names not held, names held twice, names now synonyms, taxonomic acts that differ.
2. Galls (which Gall each description is): Gall generation, several matches, generation pairs, undescribed Galls, new Galls, generations outside their group, Gall renames.
3. Disputes (which disputed statements go in): statements the checkers questioned, Sources of the same date that disagree.
4. Traits (what the Source's words mean): trait terms.
5. Hedges (whether a hedged statement is stated): statements set aside as hedged.

- An overview page (today's Source page) shows each step's status; "Which Source this is" is a banner there. Opening a Source goes to the first step with work left.
- The nav bar shows each step with what's left or a check mark, and marks the steps that hold approval. Within a step, no row starts open and Decide closes the row; Next goes to the following step.
- Approve appears in the nav bar on its own once nothing holds approval; the curator still clicks it to apply.
- Gallformers notes keep their own page shape for now; revisit after.

- Step navigation mockup: https://claude.ai/code/artifact/3c8998c7-d683-4342-b040-a1546ed10d94 (local `docs/plans/source-review.html`, gitignored). Real Nastasi & Davis 2022 items; Traits uses the settled term design, the other steps carry it over until their questions are designed.

- Hedges (Jeff, 2026-11-03): stay one page, grouped by what each hedge is about: names and species (synonymies, splits, new genera, species groups), the Inducer (and other associated organisms), Hosts, range, the Gall itself (where on the plant, shape, form). Each group has "Leave the rest out". Mockup v2 groups Nastasi & Davis's 39 by hand (15 / 7 / 5 / 6 / 6).
- Needed for real grouping: the producer tags each set-aside statement's topic. Today 80 of 107 open ones are slot `other` (the `unmapped` slot enum: generation, relationship_type, lethality, parasitism_mode, place, rank, taxonomic_act, other). Contract change: a topic per `unmapped` entry (names, inducer, host, range, gall, other); packages without it show their hedges under "Other".

- No "Accept all recommended" on Traits (Jeff, 2026-11-03): each term can be accepted on its own, never all at once, since a recommendation can be wrong ("each with a single insect").
- Order (Jeff): design the other steps' questions (Names, Galls, Disputes) before building any of this. Gallformers notes wait until all of this is settled and built.


## Names step design (Jeff, 2026-11-03)

- Source referred to by its short name ("Ashmead 1897"), never its full title, everywhere on the review pages.
- Each taxon option shows what it is in one line: family, author and year, its Galls and Hosts in Gallformers. At most three candidates shown as options; more go behind "Choose from N possible matches". "Create" asks for what it needs (genus, or a family's place in the tree) only once chosen. "Leave this name out" says what it drops, with counts.
- "Accept all" on Names: kept, but only for firm proposals (rules the importer applies: an exact synonym in the tree, the same name read as an old Cynips name); never for "check it" suggestions.
- Three sections, not five: Hosts; Which taxon is it (names called new, names not held, names held twice: the same question); Where the Source and the tree differ (synonyms, and taxonomic acts that differ).
- Suggestion engine fix: near-spelling suggestions stay within the Source's genus (QUERCUS PRINOS was offered Castanopsis and Lithocarpus).

- Research burden (Jeff, 2026-11-03): taxonomy questions need facts the curator now digs up in another tab. Answer in this UI, kept small: every taxon, plant or Gall offered as an answer shows its identity line (family; Galls and Hosts in Gallformers; for plants, WCVP status) and links to its admin page in a new tab. No research tool. Jeff to decide ~10 of Ashmead's Names on the current page and list what he had to look up; that list sets what else goes on the questions, before Galls is designed.
- Names mockup (Ashmead 1897, all 26 real Names questions): https://claude.ai/code/artifact/5b871d5f-0856-4177-9925-7d38f508368e (local `docs/plans/names-step.html`).
- Data findings: the tree records no authorship for these taxa (identity lines can't show author and year); the tree's synonyms have no Source or date (`taxon_names`, carried over from the old data); Rhodites gracilis, R. similis and Diastrophus smilacis are "check that synonymy" though the producer did mark them new (corrected 2026-11-03; an earlier note blamed the producer): rule H proposes only when the old genus and the tree's taxon share one family. The tree holds "Rhodites" names in both Cynipidae and Diplolepididae, so the Rhodites pair can't be confirmed as one family; Diastrophus smilacis moved to Aprostocetus, in Eulophidae, a real change of family. All three rightly stay checks, and the quote ("new species") shows the curator why.
- Open: "The tree may be wrong here" on a synonym question sends the disagreement to whoever maintains the taxonomy, with the statements on the current species meanwhile; or can a curator change the synonymy from the review page?

- Rows (Jeff, 2026-11-03): no row starts open; Decide closes the row. The next row no longer opens on its own (this replaces "deciding a row opens the next open row"). Applied to all three mockups.

- Synonymy is changeable from the review page (Jeff, 2026-11-03): on a synonym question, "Ashmead is right: change the tree" makes the name a species of its own again, or moves it to another species; the change is a tree edit for every Source (through the taxonomy edit log, so it replays), and the Source's statements go on the result.
- Ten-question test (Jeff, Ashmead Names): what a curator looks up is (1) which names Gallformers already holds as aliases (synonyms) and what Facts use them; (2) for plants, what WCVP says; (3) a web search only when WCVP doesn't hold the name. So each candidate states plainly whether Gallformers already holds the Source's name as one of its synonyms ("Already holds 'Andricus wisliceni'" vs "Doesn't hold 'Andricus dasydactyli': matched on the species name"); each Host question says what WCVP holds for the name as written or its nearest spelling, its status and accepted name, and whether Gallformers holds that plant; with nothing in WCVP, links to search POWO and IPNI. "Facts that use this name" needs `attribution_names`, which is empty for the old data and fills as Sources are imported.
- Suggestion engine fix: near spellings over the whole name, infraspecific epithet included. "Quercus chrysolepis var. vaccinifolia" missed WCVP's "Q. chrysolepis var. vacciniifolia (Hittell) Engelm.", a synonym of Quercus vacciniifolia (held), and fell back to the species, which is a different plant.


## Galls step design (Jeff, 2026-11-03)

- Each candidate Gall is compared side by side with what the Source says, field by field (agrees / differs / not stated), on what curators judge Galls by: Host, where on the plant, detachable, generation (which implies season); the descriptions below. A Gall whose description quotes this Source says so ("Gallformers' description comes from Osten Sacken 1862"). Hosts compare after the Names step has resolved them.
- A real conflict cancels "firm": a different part of the plant (roots vs stem, stem vs fruit; different leaf values don't count, all being `leaf`) or a different form. "Accept firm matches" skips it and the curator decides. Today that catches C. q. juglans (Osten Sacken's corky branch gall vs Gallformers' acorn plum gall) and Callirhytis rhizoxenus (roots vs stem).
- An undescribed match is never firm: a curator always confirms it (the pin oak "wart-like excrescences" was firmly matched to an undescribed leaf curl).
- Long candidate lists: at most three shown, ranked by how many fields agree; "Choose from N possible Galls" for the rest ("the oak-apple found once on Q. nigra" had 12 candidates, none an oak apple).

- Galls mockup (Osten Sacken 1862, its 15 real Gall questions): https://claude.ai/code/artifact/29a176dd-d1cb-4a41-88c3-89fdf56005f7 (local `docs/plans/galls-step.html`). With the conflict rule, 5 of the 10 named-species questions stay firm; C. q. juglans conflicts (stem vs fruit); C. q. operator's "woolly twig gall" conflicts with both of Gallformers' generations (flower, fruit).
- Osten Sacken's "Q. nigra, the black-jack oak" is an error in the paper (Jeff, 2026-11-03): Q. nigra was never the black-jack oak (Q. marilandica). It resolved to Quercus nigra with no question since the name matches; only a curator can catch it, so Host rows show the Source's whole phrase, common name included.

- A Source wrong on some statements (Jeff, 2026-11-03; Osten Sacken's "woolly twig gall of C. q. operator on the black-jack oak" is really C. quercusoperator (sexgen) on Q. marilandica, and he was wrong about Host and location): choosing a Gall that conflicts opens a follow-up listing the Source's statements that disagree with it; for each, keep it or leave it out, and for a Host also "he means another plant", which records the Source's name in his sense (taxon_names `sensu`) for every use in that Source, a Names correction made from wherever the error shows up. "Leave it out" drops the statement: it never becomes a Fact; the quote stays in the Source's text (as for a dropped dispute). A conflict is a reason to look, not a verdict: the row says "Check: both Galls conflict with what Osten Sacken says", not "neither fits".


## Disputes step design (Jeff, 2026-11-03)

- Identical disputes are one question: disputes about the same statement (same type and value, e.g. host_of Quercus) list every Gall they cover; keep or drop them together, unticking a Gall for an exception. Ashmead's ten "unnamed oak → Quercus" disputes become one.
- Disputes about Trait terms move to the Traits step, as terms whose placement is disputed (9 of today's 25: "attached by a small point" as detachable, "color of a large dried pea", "convoluted" as texture, "mature in late August" as season, a broken fragment as a term…). They then no longer hold approval, as Trait terms don't. Disputes keeps statements about Hosts, range, taxonomy and Galls.
- Each side shows a one-sentence position by default; the full arguments go behind a disclosure. No Recommended on a dispute. Contract change: the producer and the checker each write a one-sentence summary of their position (until then, each side's first sentence).

- Disputes mockup (Ashmead 1897): https://claude.ai/code/artifact/0238f6b8-c978-4892-87fb-1af6f028d581 (local `docs/plans/disputes-step.html`). The ten oak disputes as one question, the Ambrosia Host (keep / keep as another plant / drop) and the Gall Ashmead never saw (keep / drop the Gall).
- All five steps now have a click-through design: Traits (term-questions), steps and overview (source-review), Names (names-step), Galls (galls-step), Disputes (disputes-step). Next: the implementation plan.


## The Source in context (Jeff, 2026-11-03)

Deciding many questions needs the Source's whole passage, not a fragment (the "unknown oak" Hosts; "the twigs of the black oak", which names a species, but which black oak depends on where). Recovers a feature planned at the start of the import effort and since dropped. The package's `document.json` (every text block in order, with its label and page) is already delivered and read at resolve time.
- "Show the passage" on every quote: expands in place to the Source's entry the quote sits in (from the heading above it to the next heading; page headers stripped), the quote highlighted, its page given.
- "Read the Source": a side panel with the whole text, opened at the passage, every quote of the current question highlighted; scroll and search freely (covers the page on a narrow screen).
- The PDF page view waits (Jeff): it would need the PDF delivered with the package (Ashmead's OCR'd PDF is 22 MB) and is the only way to check OCR damage and tables.
- Common names become Host questions (Jeff): the producer declares a Host by its common name ("the black oak", "live oak", "scrub oak") instead of setting it aside and stating only the genus; the Names step asks which plant, suggesting Gallformers' common-name match (only one "Black Oak", Quercus velutina, so it never decides) beside "another plant", "only the genus" and "leave it out", with the passage there. Replaces rule 3's treatment of unpaired common names in the producer guide; needs a re-run. Most of Ashmead's ten oak disputes would not arise.

- Disputes mockup v2 shows the Source in context with Ashmead's real text: "Show the passage" on every quote (each oak Gall has its own; the shared "red oak, Quercus rubrum" pairing has one too) and "Read the Source", a side panel with the whole text at the passage, the question's quotes highlighted, and a find box. The same two controls go on every step's quotes.


## Implementation Plan: review redesign and trait rules (2026-11-03)

**Goal:** Build the decisions above: the `leaf` value and several-value terms, the new agreement and firmness rules, the per-step review pages (Names, Galls, Disputes, Traits, Hedges) with the overview and step bar, the Source shown in context, and the contract and guide changes that feed them.

**Architecture:** Back-end rules first (Catalog vocabulary, `Import.TraitTerms`, `Import.GallMatcher`/`Proposals`, `Import.HostSuggestions`, `Import.Queue`), each behind the existing replay log where it changes the tree or vocabulary. The review UI is rebuilt as one LiveView per step under the Source, sharing one question component; the presenter (`GallformersWeb.Admin.Review.Questions`) keeps turning queue items into plain-language questions, extended with identity lines, comparisons and passages that the loader gathers. The contract (`priv/import`) gains small fields; the producer guides change; a paid re-run (one at a time, each authorised by Jeff) brings the new data in.

**Tech stack:** Elixir/Phoenix LiveView, Ecto/Postgres, Boundary, Carbonite; Python producer (`services/import-producer`) and contract (`priv/import`: schemas, `validate.py`, guides). TDD throughout; `mix precommit` clean before any commit; commits only when Jeff says.

**Mockups (the UI's spec):** Traits https://claude.ai/code/artifact/8d270e3d-fc14-4e85-a3a3-c31ed4d5f1e3 · overview and steps https://claude.ai/code/artifact/3c8998c7-d683-4342-b040-a1546ed10d94 · Names https://claude.ai/code/artifact/5b871d5f-0856-4177-9925-7d38f508368e · Galls https://claude.ai/code/artifact/29a176dd-d1cb-4a41-88c3-89fdf56005f7 · Disputes https://claude.ai/code/artifact/0238f6b8-c978-4892-87fb-1af6f028d581. Local copies in `docs/plans/` (gitignored).

### Phase A: data rules

#### Task 1: `leaf` as a plant part value, contained leaf values
**Files:** `priv/import/vocab/traits.json` (add `leaf` with its definition; seed term "on the leaf" → `leaf`; drop the leaf rule's two-category seed); a migration adding the `leaf` trait value and re-pointing the seeded term; `lib/gallformers/catalog/vocab/trait_value.ex` (`leaf_values/0`: the plant part values that are leaf values; petiole is not one); `lib/gallformers/catalog/vocab/trait_term_mapping.ex` (remove the leaf-rule exception); `lib/gallformers/catalog/identify.ex` (`traits_filter`); `lib/gallformers_web/live/id_live.ex` (drop the synthetic `leaf_anywhere` option and `expand_plant_parts/2`); `lib/gallformers_web/controllers/api/gall_controller.ex` if it filters plant parts.
**Behavior:** filtering by `leaf` matches Galls with `leaf` or any leaf value; filtering by a leaf value (e.g. `lower leaf`) matches that value or `leaf`, never another leaf value alone; `petiole` matches only `petiole`. `leaf` is never stored beside a more precise leaf value by the import (the Gall page shows both when two Sources differ in precision; no special handling). Existing data is not converted.
**Testing:** identify: `leaf` filter returns a `lower leaf` Gall; `lower leaf` filter returns a `leaf` Gall but not an `upper leaf`-only Gall; `petiole` unaffected; vocab check (`mix gallformers.import.vocab --check`) passes with the new value; the ID page offers `leaf` once, as a real value.

#### Task 2: terms that name several values
**Files:** `lib/gallformers/catalog/vocab/trait_term_mapping.ex`, `lib/gallformers/catalog/vocab/terms.ex` (a term holds one category, or several when placed so; no exceptions list), `lib/gallformers/import/trait_terms.ex` (agreement on a set of categories places the term under each), `lib/gallformers/import.ex` (`place_term/4` takes a list), the curator decision `%{"place" => [c1, c2]}`.
**Behavior:** a term is placed under one category or under each value its words name ("green-yellow" → green + yellow; "protruding from both sides" → upper leaf + lower leaf). Readers agreeing on the same set places it by agreement. Replay records the set.
**Testing:** agreement on {green, yellow} places under both and writes two Facts per use; a curator's two-category placement replays; a one-category term is unchanged.
**Depends on:** Task 1 (the leaf exception goes).

#### Task 3: producer silence gives way to agreeing checkers
**Files:** `lib/gallformers/import/trait_terms.ex` (`agreement/1`).
**Behavior:** a Fact whose producer suggestion is nil, with every checker placing the same category, agrees on that category. All three nil is still agreement on no category. A real split (a reader naming a different value) is still a question.
**Testing:** producer nil + both checkers globular → placed by agreement ("round"); producer mono + c1 mono + c2 poly → question; all nil → fits none by agreement.

#### Task 4: Gall comparison, conflicts and firmness
**Files:** create `lib/gallformers/import/gall_comparison.ex` (compare a batch Gall's statements with a Gallformers Gall on Host, where on the plant (coarse: leaf values are one), detachable, generation and season, and form; each field agree / differ / conflict / not stated); `lib/gallformers/import/gall_matcher.ex` and `lib/gallformers/import/proposals.ex` (a proposal with a conflict is not firm; an undescribed match is never firm, only a best match).
**Behavior:** a conflict is a different coarse plant part or a different form. Hosts compare after name resolution. Candidates are ranked by agreeing fields.
**Testing:** roots vs stem conflicts (Callirhytis rhizoxenus); lower leaf vs leaf midrib agrees; an undescribed best match is proposed but not firm; firm proposals without conflicts unchanged.

#### Task 5: Host suggestion fixes
**Files:** `lib/gallformers/import/host_suggestions.ex`, `lib/gallformers/import/name_variants.ex`.
**Behavior:** near spellings are matched over the whole name, infraspecific epithet included ("Quercus chrysolepis var. vaccinifolia" finds WCVP's "var. vacciniifolia", a synonym of Quercus vacciniifolia); near-spelling suggestions stay within the Source's genus ("QUERCUS PRINOS" is offered no Castanopsis or Lithocarpus).
**Testing:** both cases with stub WCVP records; existing suggestion tests pass.

#### Task 6: common-name Hosts as questions
**Files:** `priv/import/schema/*.schema.json` and `validate.py`, `lib/gallformers/import/validator/checks.ex` (a host taxon may be declared by a common name, flagged as such); `lib/gallformers/import/resolver.ex` and `host_suggestions.ex` (a common-name Host is always a question; suggestions from `taxon_common_names`, never firm); presenter options "Only the genus" and the usual ones.
**Behavior:** "the black oak" → question with Quercus velutina suggested (Gallformers' "Black Oak"), "Another plant", "Only the genus: Quercus", "Leave this Host out".
**Testing:** a common-name host resolves to a question with the common-name suggestion; "only the genus" records the genus Host.
**Depends on:** the guide change in Task 14 to produce such Hosts.

#### Task 7: notes saved on their own
**Files:** a migration creating `queue_item_notes` (item, author, text, inserted_at; audited); `lib/gallformers/import.ex` (`add_note/3`, `list_notes/1`); `lib/gallformers/import/queue.ex` (a decision no longer carries the note; existing `"note"` values shown as notes).
**Behavior:** a note saves at any time, decided or not, and stays with the item for the next curator; it is not part of the decision and is not replayed as one.
**Testing:** note on an open item; note survives deciding and undoing; old decision notes still display.

#### Task 8: Gall decisions that drop statements or re-read a Host
**Files:** `lib/gallformers/import/queue.ex` (Gall decision shape: `%{"gall_id" => id, "drop" => [fact refs], "host_reading" => %{"name" => as_written, "taxon_id" => id}}`), `lib/gallformers/import.ex` (apply drops; record the reading), `lib/gallformers/taxa.ex` (a name in a Source's sense, `taxon_names.sensu`), replay kinds as needed.
**Behavior:** choosing a Gall can drop individual statements (they never become Facts; the quote stays in the Source's text) and can say the Source means another plant by a Host name, which re-resolves every use of that name in that Source (Osten Sacken's "Q. nigra" → Quercus marilandica).
**Testing:** a dropped statement writes no Fact; the reading re-resolves all statements using the name in that package; both replay.

#### Task 9: synonymy changed from the review page
**Files:** `lib/gallformers/import/queue.ex` and `host_decisions.ex`-like module for name decisions (synonym section: `%{"split" => true}` or `%{"synonym_of" => taxon_id}`), using `{:remove_synonym, name}`, `{:create_taxon, attrs}` and `record_synonym_added/4` through `record_taxonomy_edit/2`.
**Behavior:** "Ashmead is right: change the tree" makes the name a species of its own again (under its genus, the Source as authority) or a synonym of another species, for every Source; the Source's statements go on the result; Facts on the old species stay.
**Testing:** split creates the taxon and moves the name; move re-points the synonym; both replay; the decision resolves the item.

#### Task 10: grouped disputes; Trait disputes to Traits
**Files:** `lib/gallformers/import/queue.ex` or presenter grouping (disputes about the same statement: same type and value, e.g. host_of Quercus); `lib/gallformers/import.ex` (`decide_group/3`: keep all, drop all, keep with exceptions → one decision per item); `GallformersWeb.Admin.Review.Questions` (a dispute about a trait Fact is shown on Traits as a disputed term and does not hold approval: `blocking?/2`).
**Testing:** ten host_of Quercus disputes form one question; keep with two exceptions decides ten items; a trait dispute no longer holds approval.

#### Task 11: hedge topics
**Files:** `priv/import/schema/common.schema.json` (`unmapped[].topic`: names | inducer | host | range | gall | other), `validate.py`, `checks.ex`; presenter groups Hedges by topic (missing topic → Other).
**Testing:** schema accepts and requires-or-defaults the topic per format version; grouping by topic; old packages show under Other.

#### Task 12: one-sentence positions in review.json
**Files:** `priv/import/schema/review.schema.json` (`summary` on a finding and on its response), `validate.py`, `checks.ex`; presenter shows the summaries (falls back to each side's first sentence).
**Testing:** validator accepts summaries; presenter falls back when absent.

#### Task 13: what the questions need from the database
**Files:** `lib/gallformers_web/live/admin/review_live/loader.ex` (or a new `review_live/context.ex`), `lib/gallformers/import.ex` / `lib/gallformers/sources.ex` reads.
**Behavior:** for a taxon candidate: family, Galls and Hosts in Gallformers, its synonyms, and whether it holds the Source's name (exact, close spelling, same epithet in another genus, or not at all); for a Host: what WCVP holds for the name or its nearest spelling, status, accepted name, and whether Gallformers holds it; for a Gall candidate: the comparison (Task 4), photos and Source counts, and whether its description quotes this Source; for every quote: its passage (the Source's entry, heading to heading, page headers dropped) from the package's `document.json`, and the whole text for the reader panel.
**Testing:** each read on fixtures, including a passage spanning a page break and an entry whose heading is a genus line.

#### Task 14: producer and checker guides
**Files:** `priv/import/PRODUCER_GUIDE.md`, `VERIFY_GUIDE.md`, `GALLFORMERS_STATEMENTS.md`, `services/import-producer` prompts.
**Behavior:** `leaf` ("the most precise location the Source supports; `leaf` when it supports no more"), replacing the two-Fact leaf rule; several-value terms; hedge topics; one-sentence summaries; common-name Hosts declared by the common name (replaces rule 3's genus fallback); tighter terms (a term is the Source's word or phrase for one Trait, not a clause: "sometimes three or four together…" is not a shape term); mark a species the Source calls new as new.
**Testing:** the contract examples validate; golden scoring after the re-run.

### Phase B: the review pages

#### Task 15: Source overview and step navigation
**Files:** `lib/gallformers_web/router.ex` (`/admin/review/sources/:id` overview, `/admin/review/sources/:id/:step` for names, galls, disputes, traits, hedges), `review_live/source.ex` (overview), create `review_live/step.ex`, `components/review_components.ex` (step bar).
**Behavior:** overview lists each step with what's left, how many have a recommendation, and whether it holds approval; opening a Source goes to the first step with work left. The step bar on every page shows counts or a check and marks steps that hold approval; Approve appears in it once nothing holds approval, and asks to confirm, saying open Traits and Hedges stay. Each step page has Previous / Next. No row starts open; Decide closes the row. "Which Source this is" is a banner on the overview.
**Testing:** LiveView: step routing, counts, Approve appearing only when Names, Galls and Disputes are settled.

#### Task 16: the question component
**Files:** `components/review_components.ex` (replace the item row's expanded layout), `review_live/item_row.ex`.
**Behavior:** question and scope; quotes with "Show the passage"; options with one-line summaries, Recommended (with who chose it), follow-up inputs only for the selected option; Decide with its effect stated, disabled with the reason until complete; Notes area (always shown, Save note); disclosures for details. The Source is named by its short name ("Ashmead 1897") everywhere.
**Testing:** component tests for each state (nothing chosen, follow-up incomplete, complete, decided with Undo).

#### Task 17: Traits step
**Behavior:** per the Traits mockup: readers named ("Chosen by the producer and checker 1"), the categories readers chose as options, Another, More than one, It depends on the Gall (rows per Gall, recommended per Gall, fill button), Fits no, Keep as text; disputed terms (Task 10) here too. No accept-all.
**Depends on:** Tasks 2, 3, 10, 16.

#### Task 18: Names step
**Behavior:** three sections (Host plants; Which taxon is it; Where the Source and the tree differ); identity and alias lines; WCVP panel on Hosts; at most three candidates; create with genus or place; leave out with counts; change the tree (Task 9); common-name Hosts (Task 6); Accept firm matches per section.
**Depends on:** Tasks 5, 6, 9, 13, 16.

#### Task 19: Galls step
**Behavior:** two sections (Galls of named species; Undescribed Galls); comparison table per candidate; conflict tags; best match for undescribed; another generation's Gall with a generation choice; per-statement keep / leave out and "he means another plant" (Task 8); Accept firm matches.
**Depends on:** Tasks 4, 8, 13, 16.

#### Task 20: Disputes step
**Behavior:** grouped disputes with per-Gall exceptions; both positions in a sentence each; full arguments behind a disclosure; keep a Host as another plant; no Recommended.
**Depends on:** Tasks 10, 12, 16.

#### Task 21: Hedges step
**Behavior:** one page grouped by topic, each group with "Leave the rest out"; State it with its follow-up.
**Depends on:** Tasks 11, 16.

#### Task 22: Read the Source
**Files:** `components/review_components.ex` (passage block, reader panel), the step LiveView.
**Behavior:** "Read the Source" opens the whole text beside the questions at the passage, the question's quotes highlighted, with a find box; covers the page on narrow screens. PDF page view waits.
**Depends on:** Task 13.

### Phase C: re-run
#### Task 23: re-run the Sources and notes
Rebuild the term table and vocabulary, then re-run the five Sources and the trial notes with the new guides, one at a time, each run authorised by Jeff; compare with the golden set; deny superseded local packages.

**Not in this plan:** the Gallformers notes page (after this is built); the PDF page view; API and site search for Source terms.


## Build status (2026-11-03)

Tasks 1–22 built and verified; `mix precommit` clean (3,176 tests, credo clean), contract tests 141, producer tests 110; dev DB migrated (queue item notes, `leaf`, terms with several values) and vocab `--check` up to date; local packages 16–30 re-resolved under the new rules. Nothing committed.

Additions beyond the plan: a silent producer needs two agreeing checkers (one checker's value is no agreement); `pending_trait_terms.settled_category` became `settled_categories`; a name decided new may take a `parent_id`, a new Gall a `generation`; a Host dispute may be kept with its Host read as another plant (single or grouped); an open Trait dispute at apply is stored as a waiting term so the Gall shows the words.

Known gaps: no Undo for a decided item (decisions that change the tree need their own design); "Another taxon"/plant search results lack identity lines; "He means another plant" on a Gall only when the Source names one Host for it; per-Gall Trait decisions take one value; a grouped Host reading can't be combined with unticked Galls in the UI; the reader's find re-renders the whole text; the old several-species comparison still shows beside the identity lines.

Remaining: Task 23, the paid re-run (one Source at a time, each authorised by Jeff). Open before it: does a bare "an unknown oak" become a common-name Host question (curator picks "Only the genus: Quercus"), or does the producer state Quercus and ask only for names like "the black oak"?

- Bare oaks (Jeff, 2026-11-03): an unnamed "oak" always needs a curator, with enough context to decide, and is usually assigned to a section, not the genus (the tree holds Quercus sections: Lobatae, Quercus, Protobalanus, Virentes, Cerris, Ponticae). So a common-name Host question offers the genus's sections first (from the tree), the genus only as a last resort; same for a Host dispute kept "as another plant".


## Re-run with the d213 guides (v5, 2026-11-03)

Jeff: "Just run them all." Five Sources, one at a time, $30.33 (Ashmead $7.24, Osten Sacken $6.65, Floate $6.53, Nastasi & Davis $8.30, Aphis $1.60). All valid; delivered locally as packages 31–35 (keys `<dir>-v5`); v4 packages 16–20 denied as superseded. Output `services/import-producer/output/v5-2026-11-03/`, script `docs/plans/v5-rerun-sources.sh`. Guides tightened just before: a bare common name ("an unknown oak") is a common-name Host with no rank; a pairing ("the red oak, Quercus rubrum") covers only the name it pairs.

New rules took: Ashmead's 13 common-name Hosts are declared by their words (no genus Quercus Host stated, so the ten oak disputes are gone; they are Host questions offering the oak sections); every finding and response has its one-sentence summary; every hedge has a topic.

Golden set, possible regressions (19, against 12 in v4): Ashmead 1 (f260 season Fall, as before); Osten Sacken 6 (C. Q. inanis name act not declared; f26 walls "shell thick" left blank; f44 walls thin; f62 description 0.58; f79 color "rusty" left blank; f127 oak apple as before); Floate 7 (Populus nigra var. italica not attached as Host for three Galls though declared and used for six; f10 form pocket; f44 walls ostiole; f51 season Summer; f110 description 0.56); Nastasi & Davis 3 (f58 "round" left blank, now a question; f269 cells; f366 color red); Aphis 2 (as before). Blank categories are the new guide's "null unless the words plainly mean one value" (placed later if the checkers agree); the rest look like run-to-run variation in what the producer picks up, not a rule the guides broke.

Also built after "Just run them all": common-name Host questions offer the genus's sections first (Quercus sect. Lobatae "Red Oaks", sect. Quercus…), the genus last; keeping a disputed genus Host, or a Gall's genus Host, "as another plant" sets that plant for those statements only (`host_taxon_id`), never a package-wide reading (a reading of a genus name is refused). `mix precommit` clean at 3,203 tests.


## Cost correction (2026-11-05)

The cost script missed phase 5 (the checkers record their cost in `phase5.record.json`, not `run.json`). True costs: v5 re-run **$44.86** (not $30.33: Ashmead $10.92, Osten Sacken $9.63, Floate $9.35, Nastasi & Davis $12.44, Aphis $2.51); v4 re-run **$45.85** (not $32.44). Split of v5: phase 3 (Galls) $16.66, phase 5 Opus checker $9.71, phase 6 (responding) $7.54, phase 2 (taxonomy) $6.13, phase 5 Sonnet checker $4.82. Caching already works (almost all input is cache reads); the cost is Opus output and the doubled checking. About $9 a Source on these; levers to weigh for 1,000+ Sources: one checker (−22%), a cheaper model for phases 5–6, several short Sources per run.

Missed-names check (prototype, no cost; scratch `missed_names2.py`): names Gallformers' tree knows that a Source prints but no batch declares — 2 to 10 per Source, a list a curator can scan; it would have caught Osten Sacken's missing "Cynips quercus inanis". A per-Gall variant (names in a Gall's cited passages it doesn't use) is noisy, since old papers name other species in comparisons; Floate's missed italica Hosts sit in passages those Galls don't cite, so neither variant catches that kind.

Missed-names check, back end built (2026-11-06; no screen yet): `Gallformers.Import.UnusedNames` (`for_package/1`, `list/2`) with `Taxa.names_held/2` (one query) and `Resolver.genera/2` made public. It reads the Source's text blocks (headers and footers skipped), expands abbreviated and Cynips-style names, and reports tree names no batch declares, in the order printed, with items and pages. Dev results: Ashmead 6, Osten Sacken 4, Floate 8, Nastasi & Davis 7 (real misses such as A. spongifica, Rhodites ignota, CYNIPS QUERCUS PISUM, Pemphigus obesinymphae, Diastrophus austrior, alongside comparison Hosts a curator dismisses). **Decided (Jeff): a name declared in any batch counts as declared.** The check answers "did the producer skip this name?"; a missing name act for a name the gall batch uses (Osten Sacken's "C. Q. inanis") is a different gap that text matching can't see, left to the checkers and the curator. Counting only the taxonomy batch would add every used Host and gall-former (about 14 for Osten Sacken, 34 for Nastasi & Davis). Next: show it on the review Source page.

