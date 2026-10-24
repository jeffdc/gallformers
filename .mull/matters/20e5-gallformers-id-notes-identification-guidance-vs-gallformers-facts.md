---
status: raw
created: 2026-10-11
updated: 2026-10-23
epic: taxonomy
relates: [8546, 294c]
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

## Remaining work

- Convert the notes: split each into statements of Fact (imported as Gallformers statements), commentary (page content) and copied passages (attributed to their paper).

