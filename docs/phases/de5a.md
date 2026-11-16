# Decisions first

The decisions that shape work in more than one phase, or that Jeff has said must happen first, settled before any building (Jeff, 2026-11-16). Every other phase waits for this one, except *The UI*, whose accounting runs alongside it. A decision that only affects work inside one phase stays in that phase.

## The decisions, in order

Until mull orders items within a phase, this is the order:

1. **The old public API's fate** (item 3c4f). Jeff: as soon as possible. Whether anyone uses it, whether it's disabled in production until release, and its version; it also unblocks GitHub's API-version check on the taxogall pull request (Housekeeping, 4a47).
2. **Is all data a Fact?** (item d178), then **exactly which data is editorial** (it follows from the answer). Shapes *One write path*, *Migration through the import* and the UI's interfaces.
3. **The existing Sources:** the analysis (6936), then the decision (7a50). Comes before any migration work (Jeff, 2026-11-14); shapes *Migration data*, *Migration through the import* and *Process Sources on preview*.
4. **What the old Gallformers notes contain** (5352) and **how to date the Facts from undescribed-Gall notes** (76f1). Analysis first (Jeff, 2026-11-15); the dating answer settles *Migration through the import*'s item 15ca and backlog bug 5248.
5. **Ranges:** how they work for the ID tool (the same as the range shown) and for curating range data. Shapes *Public site, settled*, *One write path* and the UI.
6. **How a curator produces a Source package and gets it into the system, and where the producer runs** (274b). Shapes *Import at scale*, *Preview environment*'s upload page and *Process Sources on preview*.
7. **The taxonomy API**, in its own design session (Jeff, 2026-11-15), learning from prior art such as iNaturalist's curation of swaps, splits and merges. Shapes *One write path*'s taxonomy writes and the UI's taxonomy screens.

## The existing Sources: what's known

### Why

The old site's data stays as undated Gallformers legacy data, and Sources are reprocessed into the new model (plan doc, *The old site's data and the Gallformers notes*). That turns the way the old data was treated around, and nobody has yet decided what happens to the existing Sources themselves (Jeff, 2026-11-14). The answer decides what the migration carries and what *Process Sources on preview* has to do, so this phase comes before any migration work.

### What's known (dev copy of production, about 2026-10-23)

- 933 Source records. 875 are attached to Galls through 8,202 per-Gall citation rows (`species_source`).
- 8,081 of those rows carry a description: text copied from the Source for that Gall. 2,999 carry a link to an outside page.
- The migration copies 6,679 citation rows verbatim into `legacy_citations` (every Source but the Gallformers notes), and keeps the old site's Facts as Gallformers legacy data whatever happens here.
- The Gallformers notes (Source 58) are their own phase and are out of scope here.

### What the decision covers

Everything related to the existing Sources (Jeff, 2026-11-15): the Source records, their per-Gall citations, the copied excerpts, the per-Gall outside links, and whether each Source can and should be reprocessed through the producer. Possible fates include reprocessing it, keeping it as a reference only, or keeping its excerpts as text; the answer may differ by kind (papers, books, websites, databases).

The analysis also covers the backscan's feasibility, which no record tracked: getting the documents (around 330 on BHL, many paywalled or on ResearchGate, books with no digital copy), long Sources (catalogues and keys of 150 to 350 pages), websites with one page per species, the subscription's rate limits, and whether Jeff has scans of Gagné 1989 and Russo 2021 (the second and third largest Sources).


## Done when

Each decision above is made by Jeff, recorded in the decision log, and the docs of the phases it shapes say what it means for them (changes proposed to Jeff first).

Sources: Jeff, 2026-11-12 to 11-16 (decision log); the plan doc's *Design work still to do*.
