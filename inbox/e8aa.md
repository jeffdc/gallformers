---
kind: decision
text: 'Phase 2: a paper agreeing with the tree raises no question but stays ''awaiting'''
plan: taxogall
source: matter 50ff, 'For Jeff's review' (the 2026-11-06/07 build); replaces entry 351c
by: /Users/jeff/dev/gallformers
created: "2026-11-12T02:23:22Z"
---

Context (phase 2, f923): a Source's taxonomic statement (placement, accepted name, synonymy, rank, split, common name) competes by the Source's date, but counts only once a curator accepts it; until then it is recorded and 'awaiting'. Statements of the Gallformers Sources (Gallformers' own and the undated 'Gallformers legacy data', which holds today's tree at cutover) need no acceptance. A question is raised only for a statement newer than every counting statement in its slot. 
Chosen: a Source whose taxonomic statement agrees with the tree raises no question, and its statement stays 'awaiting' (not accepted).

Why (the build notes state the rule without a reason; this is how it follows from the rules): no question is needed, because nothing in the tree would change; the volume rule only asks about statements that differ and are newer. The tree's value keeps counting through whatever already supports it (usually the undated legacy statement, which needs no acceptance), so the Fact stays current.

Consequence: the agreeing paper is shown as awaiting, and the current position stays credited to the legacy data (or the earlier accepted paper), not to the agreeing paper, until a curator accepts it (e.g. through 'Accept the rest of this paper'). If the legacy support is later outranked, the agreeing paper doesn't count unless accepted. Phase 1 decisions a curator followed are accepted by the cutover carry-over (Import.TaxonomyCarryOver), but plain agreement is not.

Alternative: accept agreeing statements automatically, so the tree's position is credited to the paper (simpler provenance, but an acceptance no curator made).

Code: Import.TaxonomyQueue.difference/4 (nil when a statement agrees), Import.ApplyTaxonomy.
