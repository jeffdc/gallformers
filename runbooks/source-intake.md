# Source Intake

Advice and gotchas for the people bringing Sources into Gallformers during the backscan: choosing what to run, running the producer, and reviewing the result. How to run each phase is in the [import producer README](../services/import-producer/README.md); this runbook is the judgement around it. Add to it whenever something catches you out.

## Choosing what to run next

### Newest first, per group of taxa

Within a group of taxa (a genus, a tribe, a host group), take the most recent revision or catalogue first and work back to the older papers.

Why: Gallformers takes its taxonomy (placements, accepted names, synonymy) from the literature. A Source's taxonomic statement counts only once a curator accepts it, and the newest accepted paper wins. When you accept a paper, the open questions about the same taxa from older papers close as history, and papers older than the latest accepted one stop raising questions at all. Starting with the 2021 revision means the 1860, 1900 and 1950 papers record their positions as history without asking you anything. Starting with 1860 means accepting four moves of the same wasp, one per paper.

Order changes how many questions you answer, never the outcome: which statement wins depends on the papers' dates, not on when they were reviewed.

The tree carried over from the old Gallformers data is undated, so any accepted paper outranks it. Disagreements between a paper and today's tree are expected and are the point: they are how outdated positions in the old tree get caught. Other than undescribed Galls, Gallformers makes no taxonomic placement without a third-party Source.

Questions about following a paper's placement, accepted name or synonymy don't hold up the Source's approval: they wait in one taxonomy queue across all Sources. If you don't follow a paper, decline it with a reason; the tree keeps following the latest paper you accepted, and the reason is shown with the declined paper.

(The question limits, the taxonomy queue and declining are the phase 2 design in matter `f923` and are not built yet.)

### Check the Source's date

The date the Source was authored decides which statements win, for traits and ranges as much as for taxonomy. Check it against the work itself (the publication date, not the reprint or the scan date) before you approve.

### Cost

About $9 a Source for papers of 10 to 50 pages ($2.50 for a short web page). Phase 3 (the Galls) is the biggest share and grows with the Source's length. Sources over about 100 pages haven't been tried.

## Preparing the Source

- **Web pages:** supply the page's URL and the date you read it; the producer can't know them.
- **Scans:** the producer re-OCRs and keeps the better text. `convert.json` says which text it used; glance at its quality figures for an old or faint scan.
- **Photos aren't read.** The statements say what the text says, even where a photo shows otherwise.
- **Complex tables convert poorly.** If a Source's key content is in tables, check those statements closely.

## Reviewing

The review pages are at `/admin/review`. Each Source's questions come in steps: Names, Galls and Disputes must be answered before approval; Traits and Hedges can be left. Facts is optional, but look at it before approving.

### Names

- **Common names can be Hosts.** A Source that says "on oak" names a Host. A bare "oak" with no species needs your call, and usually belongs to a section of *Quercus* rather than the genus.
- **A Host neither Gallformers nor WCVP holds:** use "Create a new plant ↗" on the question. It opens the new-plant page in a new tab with the name filled in; save, then search for the plant on the question.
- **Old papers' original combinations** (a species first named in a genus it has since left) are history, not a move. They don't raise questions.

### Galls

- **Undescribed Galls are always confirmed by a curator.** This is the one place Gallformers makes a taxonomic call of its own, so read the passage before confirming.

### Traits

- Each term can be accepted on its own; there is no "accept all", on purpose.
- When the producer said nothing about a term and both checkers agree with that silence, the recommendation follows them.

### Facts

- The Facts page shows what approving would write, grouped by Gall, each Fact marked new, already held, or in conflict. It updates as you answer questions.
- **A Fact you didn't expect may come from another Source.** InfluentialPoints' *Aphis rubifolii* seemed to add the whole genus *Rubus* as a Host; that came from the old Gallformers data, not from InfluentialPoints. Check which Source a held Fact is credited to before blaming the one in front of you.
- Edits here (drop a Fact, change a Host or a trait value, add a note) apply to this Source's statements only.

### Names the producer skipped

The producer can miss a name the Source prints. A list of names the Source prints that Gallformers' tree holds but the batches never mention is being added to the review (matter `d213`). Most entries are Hosts or species named only in comparisons; dismiss those. The ones to act on are species the Source treats that have no statements. It can't see a name that is used but whose taxonomic act was missed, so watch for those on the Names step.

### Undo

Undo of a decided question works only while nothing depends on it: the Source isn't approved, and nothing the decision changed has been edited since. Otherwise, fix it in the taxonomy admin. (Not built yet.)
