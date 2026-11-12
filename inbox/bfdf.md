---
kind: question
text: OK to remove the six Fact-editing mockups (gall_facts_live, genus_facts_live, species_facts_live, FactEditMock, fact_inspector_live, source_reading_live)? You wanted to see the real UI first.
plan: taxogall
source: matters 87a1 and d3b0, 'Carried from 87a1'; Jeff's 2026-11-09 audit; replaces entry c9e6
by: /Users/jeff/dev/gallformers
created: "2026-11-12T02:23:22Z"
---

In dev/gallformers_web/dev/mockups/. Deleting a mockup also deletes its route (`lib/gallformers_web/router.ex`, the `:dev_mockups` live_session) and its `docs/design-system/mockups.md` entry. As of a0434bcf `mockups.md` lists none of these (it says 'There are no mockups at the moment', which is stale) and its rule is 'Delete a mockup once its page is built'.

Why they were kept: the inspector build planned to remove the Facts-panel mockups once the Gall page matched the inspector mockup, with Jeff's OK, and the inspector mockup then too; on 2026-11-08 Jeff said keep them until he has looked at the real UI. The real UI is the Gall page (`/gall/:id`, `?edit` for Edit mode): `fact_ref` values opening the Fact inspector, Edit-mode actions and reading fixes, Add from observation, the tray grouped by authority, a Fact's History, and Facts no longer current opened from the full record.

What each is:
- `gall_facts_live` (`/dev/mockups/gall-facts/:id?edit`), `genus_facts_live` (`/dev/mockups/genus-facts/:name?edit`), `species_facts_live` (`/dev/mockups/species-facts/:id?edit`): the earlier 'every Fact edit in the Facts panel' design (question 4974). The genus and species ones are the only mockups of an Edit mode for taxonomy on rank and species pages, which are still to be designed through the inspector.
- `FactEditMock`: the shared data and mock tray of those three and of `fact_inspector_live`; it goes only with all four.
- `fact_inspector_live` (`/dev/mockups/fact-inspector/:id`, `?edit`, `?withdrawn`): the inspector mockup, including History and the withdrawn-Fact state; superseded by the built Gall page.
- `source_reading_live` (`/dev/mockups/source-reading/:package_id`): not a Fact-editing mockup from 87a1/d3b0 but the review's one-view mockup from the import-review work (matters 6611, f14c, d3b0), the visual reference for replacing a Source's review with the one-at-a-time review; it does not use `FactEditMock`. Removing it is a separate call from the other five.
