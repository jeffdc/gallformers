---
status: raw
created: 2026-10-11
updated: 2026-10-30
epic: taxonomy
relates: [294c, a856, 6611]
---

# Gallformers ID Notes: identification guidance vs Gallformers Facts

# Gallformers ID Notes: identification guidance vs Gallformers Facts

Exploration started 2026-10-11 (Jeff): the Source "Gallformers ID Notes" (id 58, 1,323 per-species notes, ~400 characters on average, no dates) may hold two different things — (1) how to identify a Gall, and (2) Facts attributed to Gallformers as a Source. Discovery first: find the domain's own words before mapping anything to the contract. Part of the pipeline trial (`8546`) as a separate track; relates to the contract (`294c`, `GALLFORMERS_STATEMENTS.md`) and the domain doc.

## What the notes hold (2026-10-11)

Rough text signals over all 1,323 notes (heuristic; one note often mixes kinds):

| Kind | Example | Signal count |
|---|---|---|
| Facts Gallformers states | "Carya laciniosa added as a host based on [this observation]"; "Observed in Illinois in July"; descriptions of undescribed galls | 145 host-from-observation; 492 "observed in …"; 221 start as a gall description |
| How to identify | "closely resembles … Andricus balanaspis … the host oak is the only unambiguous way to separate the two" | 403 |
| Remarks on the state of knowledge | "declared a synonym … however it is listed as valid in Thomas 2012"; "Little has been published …"; "This is Joyce Gross' gall type #2" | 140 taxonomic; 796 contain links |

- **778 of the notes (59%) are on undescribed galls.** For those, Gallformers is often the only Source: the note is the gall's description.
- **381 notes hedge** ("added tentatively as a host based on this unconfirmed observation").

## Decisions (Adam and Jeff, 2026-10-17)

The earlier questions (look-alikes as a concept; remarks as statements or page content; tentative Facts) are closed:

- **No look-alikes concept.** Look-alikes are inherent in a matching set of Traits.
- **Gallformers' statements of Fact:** Hosts added from iNat Observations, including "tentative" ones (just Facts; the single Observation is their evidence); descriptions of undescribed Galls; where and when a Gall was seen (recorded occurrences, the new `occurrence` Fact kind); adjudications of conflicts between Sources, with a reason. These import as a Source: the notes become a document, then Gallformers statements per `priv/import/GALLFORMERS_STATEMENTS.md`.
- **Commentary that isn't a Fact:** bigger-picture summaries of the literature and of the state of knowledge, open hypotheses, pointers to people and resources. Stays as page content, outside the Facts.
- **Passages copied from published papers** belong to that paper as a Source.

Recorded in `docs/import/producer-guide-background.md`, "Gallformers ID Notes".

## Decision: how notes are handled (Jeff, 2026-10-24)

- **A note is Gallformers' document for its Gall.** It stays whole and is shown on the Gall page as "Notes on ID and Taxonomy"; it is never cut down or rewritten to its commentary. Facts are extracted from it with quotes, like any Source document, so commentary, ID tips and links simply stay in the text (they go to `unmapped`, as a paper's background does).
- **Notes migrate verbatim** as each Gall's general note. ~~They are not part of the pre-release backscan.~~ **Changed (Jeff, 2026-10-28): all of the notes are processed before the public release,** as part of the backscan on preview; see *Handling the notes by category*.
- **They are processed through the normal pipeline**, not a bespoke tool: the note becomes `document.json`, the producer writes a Gallformers gall batch quoting it, and it is validated, reviewed and approved like any batch. This is the same path `8567` rule 12 plans for all curator knowledge, so nothing here is throwaway.
- **Going forward,** a curator edits the note and the edit is re-extracted. Each note version carries its edit date, so new statements are dated; only the legacy notes have no date.

## Remaining work

- ~~**Contract (`294c`)**~~ **Built 2026-10-30 (uncommitted):** a Gallformers batch can carry `source.note` (`gallformers_gall_id`, `stated_on`) and `source.document`, and quotes the note (one text item, `#/texts/0`); statement evidence is refused in a note batch (both validators). On import the quoted text is stored as that Gall's note version unless Gallformers holds it already (`Sources.store_note/5`, idempotent), the quotes point at its item, and each attribution takes the note's date with what it quotes as its statement text (`Import.Attributions.with_note/2`). A note of a Gall Gallformers doesn't hold is a queue item. `GALLFORMERS_STATEMENTS.md` has "Reading a Gall's note": identification tips, comparisons, the state of knowledge and pointers are left out (not `unmapped`, as a paper's background is left out); credited statements, rulings, personal communications, placeholders and hedges go to `unmapped` with a note saying which. Example: `priv/import/examples/gallformers-note/`.
- ~~**Generator**~~ **Built 2026-10-30:** `mix gallformers.import.notes --dir DIR [--undescribed|--described] [--limit N] [--stated-on DATE] [ids]` writes `note-<id>/` (document.json, note.json with the Gall's Inducer, generation and Hosts); `produce note <dirs>` adds document.txt and the empty taxonomy batch; phases 3–6 as usual (no phase 2). Smoke-tested free on Galls 1114, 1518, 2309.
- **Cost:** a note's prompt is mostly the contract (~118k characters for a 400-character note), so each note costs about what a short paper does per phase. ~1,300 notes one by one is likely $1,000+; batching several notes into one run would cut that. Measure on the trial before deciding.
- **Undescribed Galls are mostly legacy data, not notes (measured 2026-10-30):** 1,557 undescribed Galls, only 781 with a note; together 11,010 legacy Traits and 2,067 legacy Hosts, with no other Source. Extracting notes alone leaves most of each undescribed Gall's description "unconfirmed". Open for Jeff: re-attribute the legacy Facts of undescribed Galls to Gallformers (dated now, no LLM), with the notes adding what they say on top.
- **Note editing** in the new admin (a note editor, not a statement editor).
- **Process the legacy notes** before the public release, in batches, undescribed Galls first.
- ~~Decide the date~~ Decided 2026-10-28: about when the work is done (below). Their legacy author stays unknown, never invented.


## Handling the notes by category (Jeff, 2026-10-28)

The 2026-10-17 categories hold. How each is handled:

- **Undescribed Galls (778 notes): processed first, as a separate step.** Each description becomes Facts from Gallformers, like any Source mapped into the system. They have almost no competing Sources, so the date hardly matters.
- **Hosts, range and any other Traits a note states** are Facts backed by Gallformers.
- **Rulings between Sources** are odd. A ruling is a note taking a side in a conflict, so they are looked at case by case.
- **Commentary** stays in the note, as text, with no Facts.

**Dates:** the exact date is unimportant. It only has to settle to about when the work is done, which fits the cutover-date rule in `8567` Sources–Facts point 7. Later edits carry their own later dates.

**Conflicts (option c):** a note's Facts take the date of the import. Wherever one would supersede or withdraw a Fact from the literature, the change goes to a curator instead of happening automatically. Most note Facts don't compete: Hosts add up, and an undescribed Gall's description usually has no other Source. Conflicts come only from Traits with one value, range adjustments for the same place, and explicit denials. How many there are can't be known until a large share of the Sources is processed; count them then. If there are hundreds, consider dating by kind, where Traits with one value stay behind the literature until a curator confirms.

**Options considered:**
- **(a) Import last, dated now.** Notes win; this hurts where a note is out of date.
- **(b) Import first, undated.** The literature wins until a curator edits the note.
- **(d) Date by kind.**
- **(e) Real dates** from dates written in a note or from its iNat Observations; this covers only part of the notes.

**Range:** a Gall's range can be widened as long as it stays within the union of its Hosts' ranges. Beyond that, a Host's range must be expanded, which is common with cultivated plants (`3272`). Range from the notes is mostly recorded occurrences. **A note recording the Gall in a place its range excludes is added automatically** as a Fact, and the range updates (Jeff, 2026-10-28): it does not go to a curator, unlike other conflicts under option (c).

**Season:** "observed in July" is when a Gall was seen, not a season Fact. Extraction has to keep the two apart.

**Timing:** "release" means the public cutover. All of the notes, undescribed and described, are processed before it, on preview with the rest of the backscan; decisions carry over through the replay log. So the contract change and the generator above are now on the path to release.

**The undescribed step uses the same per-Gall notes, in an earlier batch** (Jeff, 2026-10-28): no separate Source, so there is one text for a curator to edit. The curator intake side (editing a note, re-extraction, stating a Fact directly) is still to be designed, together with the admin UI rethink.


## Curator intake: starting from an Observation (Jeff, 2026-10-28; early thinking)

Most new knowledge starts with an iNat Observation, so the curator workflow centres on it. Example: *Andricus weldii* seen on *Quercus bicolor*, a new Host. The curator points Gallformers at the Observation and says "add a Host based on this". Gallformers maps the Observation to the Gall and prompts for the Host. Jeff thinks most cases look like this.

A curator's own observations may also have to point to iNat rather than be taken on word of mouth. To settle later; keep it in mind.

Next: Jeff reads a sample of notes to see what else they hold (`docs/plans/2026-10-28-gallformers-notes-sample.md`, local).


## Undescribed Galls credited, and the first notes trial (2026-10-30)

- **Undescribed Galls (Jeff: yes):** the catalog migration now confirms every legacy Fact of an undescribed Gall (`gall_traits.undescribed`) as the Gallformers Source's own, dated the run's day (`:stated_on`; at cutover, the cutover date), with the legacy attribution kept (`CatalogMigration.UndescribedGalls`). Not in the local rehearsal database until the migration is run again (which empties the import tables).
- **Trial (Jeff authorised):** 10 notes (described 1114, 1518, 4005, 3378, 775; undescribed 2309, 2612, 5194, 2290, 5099) through phases 3–6: **$12.83, about $1.28 a note.** All 10 validate; one finding disputed (5194: whether a comparison sentence is the note's description). Submitted locally as packages 6–15; after the note-Gall matcher fix only that dispute is open. At this rate all ~1,325 notes would be about $1,700, the 544 described ones about $700. Output: `services/import-producer/output/notes-trial-2026-10-30/` (local).
- **Found by the trial:** an undescribed note's Gall was matched by guessing and one proposed a new (duplicate) Gall; a note batch's Gall is now resolved by the note's ID.
