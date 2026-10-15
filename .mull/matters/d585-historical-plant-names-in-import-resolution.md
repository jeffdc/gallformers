---
status: raw
created: 2026-10-15
updated: 2026-10-15
epic: taxonomy
---

# Historical plant names in import resolution

Old Sources name host plants by names no longer in use, and Gallformers may not hold mappings for them. Found in the Osten Sacken 1862 human check (`8546`): *Quercus tinctoria* is today's *Q. velutina*. Jeff (2026-10-15): "we do not necessarily have mappings for old plant names … This will be a challenge and we should note it as a new thing to deal with."

Why it matters: name resolution on import (`e381`) maps a Source's names to Gallformers entries through current names and synonyms. A historical plant name with no synonym entry leaves the Host unresolved, or worse, resolves to the wrong plant. Old Sources (about a quarter of all Sources are pre-1925) will hit this constantly.

To decide: where historical plant synonyms come from (POWO's synonymy, other checklists, curated aliases), and whether plant names on import resolve through them automatically or go to the admin queue (as ambiguous Gall matches do).



**Evidence from the 1862 dry run (2026-10-15):** after mechanical fixes (abbreviation expansion, capitalised headings), the only plant names Osten Sacken 1862 uses that still fail to resolve are historical ones: *Q. tinctoria* (now *Q. velutina*), *Q. obtusiloba* (now *Q. stellata*), *Q. prinos* and *Q. prinos* var. *bicolor*, *Q. virens* (now *Q. virginiana*). Every one of them is a Host in that Source.

