---
plan: taxogall
phase: db43
title: Review design-system fixes (link buttons, panels, one section heading, the shared photo grid)
stage: committed
docs:
  - .mull/matters/b230-review-cleanup-one-way-to-handle-a-name-we-don-t-have-and-the-2026-11-09-audit.md
created: "2026-11-09T20:38:17Z"
updated: "2026-11-12T02:23:22Z"
---

**What:** design-system fixes in the review and the Fact inspector (the 2026-11-09 audit's finding G). Built components replace hand-rolled markup: `button variant="link"` for raw link buttons and `panel` for hand-rolled panels. "Names we didn't read" gets its own `review_card` kind, the section heading is written once, and the Fact inspector's photo picker and `InatImportComponent` share one photo grid. This is b230's Task 8. It's small and can go in any order after item f926 (retiring `ItemRow`). Jeff's decision 7 (2026-11-09): everything in this cleanup is done here, including the Fact inspector's (87a1) code. References are as of `65531d59`; go by what the markup does.

**Rules that govern it** (`docs/design-system/README.md`; read it first): all UI uses the catalog's components (`docs/design-system/components.md`), never custom inline versions. If one almost fits, extend it and its entry. If none fits, ask Jeff, with a proposed catalog entry. The conformance baseline is never raised.

**Build:**
- **`button variant="link"` everywhere listed.** Raw link buttons are at `review_components.ex` about 1496, 1504, 1678, 1694, 1754, 1764 and 1787, `review.ex` about 750, and `question_card.ex` about 561. The variant is built (`@variants ~w(primary secondary ghost danger link)` in `action_components.ex`), but the `button` catalog entry lists only primary, secondary, ghost and danger (as of `a0434bcf`). Add `link` to the entry.
- **`panel` for the hand-rolled panels:** `card_class` with `p-6` (review_components.ex about 1780), the rail's aside with `p-panel` (about 1439), and Review's fallback unit (review.ex about 810).
- **A `:list` kind of `review_card` for "Names we didn't read".** Today it's drawn as `review_card kind={:hedges}` with its heading overridden (review.ex about 731-741). Update the `review_card` catalog entry, which describes it as "the same card, with its own heading, line and action".
- **One section-heading component.** The heading is written inline twice (review.ex about 831, review_components.ex about 1684). Check the catalog's `section` ("a heading on a rule, then content") before adding anything.
- **One photo grid** (thumbnail, tick, license), shared by the Fact inspector's photo picker (`gall_live/from_observation.ex` about 303-330, which copies the grid) and `InatImportComponent` (`live/admin/inat_import_component.ex` about 160-220). It isn't a catalog component yet. Write its catalog entry and get Jeff's approval before building it (`mull ask`).
- **Conformance rules for link-styled buttons and hand-rolled panels.** This comes from c800, not b230's Task 8. c800 left "new conformance rules for link-styled buttons and hand-rolled panels" to this cleanup, to write "once it has the cases": the cases are the ones above. Add them to the conformance check (`GallformersWeb.DesignSystem.Conformance`, `test/gallformers_web/design_system/conformance_test.exs`) so they can't come back.
- **Then run the conformance test, and lock the gain in** with `mix gallformers.design_system.baseline`. The baseline only goes down.
- `QuestionCard.leave_host?`'s wording match (finding G) is item bceb's: `Choice` gets a `leave?` flag there.

**Calls:** `ActionComponents.button/1` (`variant="link"`), `panel`, `section` (or the one heading component), `review_card`.
**Deletes:** the raw link buttons, the hand-rolled panels, the `:hedges` heading override for "Names we didn't read", the second inline section heading, and the photo grid copy in `from_observation.ex`.

**Tests (first, watched failing):** component tests for the `:list` kind and the shared photo grid. A conformance test case for each new rule, proving it fails on the known bad markup. The existing review and Fact inspector LiveView tests still pass.

**Done when:** none of the markup listed above remains. The catalog entries (`button`, `review_card`, the photo grid, the heading) match the code. The new conformance rules are in, and the conformance baseline is lowered. `mix precommit` is clean.

Also from matter c800, 'Not doing' (new conformance rules left to b230).

From matter b230, Task 8 (finding G). The shared photo grid isn't a catalog component yet: write its catalog entry and get Jeff's approval before building it. Sizing is the intake's guess: if it doesn't fit one session, mull ask to split it.

Before Model v2 this item needed f926. Items have no needs now; order work with needs between phases.
