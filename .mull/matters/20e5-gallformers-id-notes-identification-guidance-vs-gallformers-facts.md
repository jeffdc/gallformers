---
status: raw
created: 2026-10-11
updated: 2026-10-27
epic: taxonomy
relates: [294c, a856]
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
- **At release, notes migrate verbatim** as each Gall's general note, unprocessed. They are not part of the pre-release backscan.
- **After release, they are processed through the normal pipeline**, not a bespoke tool: the note becomes `document.json`, the producer writes a Gallformers gall batch quoting it, and it is validated, reviewed and approved like any batch. This is the same path `8567` rule 12 plans for all curator knowledge, so nothing here is throwaway.
- **Going forward,** a curator edits the note and the edit is re-extracted. Each note version carries its edit date, so new statements are dated; only the legacy notes have no date.

## Remaining work

- **Contract (`294c`):** allow a Gallformers batch to quote a document (its note) instead of only statement text, so every extracted Fact points at its sentence and the validator checks it; a section in `GALLFORMERS_STATEMENTS.md` on reading notes (commentary and links to `unmapped`, copied passages cited to their paper).
- **Generator:** write a Gall's note into `document.json`.
- **Note editing** in the new admin (a note editor, not a statement editor).
- **Process the legacy notes** after release, in batches.
- **Decide the date** the legacy notes' statements get: the notes carry none (`species_source` has no timestamps), and a date at processing would outrank all the literature under the recency rule (`8567` Sources–Facts point 7). Their legacy author stays unknown, never invented. Not needed until processing starts.
