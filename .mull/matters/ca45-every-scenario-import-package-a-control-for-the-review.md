---
status: raw
created: 2026-11-08
updated: 2026-11-09
epic: taxogall
relates: [6611, 294c]
---

# Every-scenario import package: a control for the review

An idea for later (Jeff, 2026-11-08: "not worth it at this time"). Raised while walking packages 115 and 119 through the new review (6611): no real Source exercises every kind of question, so testing the review by hand means hunting across Sources.

## The idea

A made-up import package that triggers every review scenario at once:

- **Hosts:** one that resolves (a control); a WCVP synonym of a plant we hold; a WCVP-accepted plant we don't hold; a WCVP Unplaced name (the Rubus case in 119); a name nothing knows; a common name with sections.
- **Names:** an Inducer we don't hold; a name we hold for more than one species; a species the Source calls new that we hold under another name.
- **Galls:** a named species with one Gall; one with several (generation); an undescribed Gall with candidates, one conflicting on a field; a Gall we don't hold; a new Gall's generation.
- **Disputes:** one Host dispute; a group of identical disputes; a Trait dispute.
- **Traits:** two or more terms with a majority answer (a batch); an ambiguous term across several Galls; one with no agreement.
- **The rest:** hedged statements; missed names (printed, held, undeclared); a title close to a Source we hold ("Which Source this is").

Dev keeps packages on local disk (`Storage.Private.LocalAdapter`), and `Import.register_package/2`, `validate_package/3` and `resolve_package/2` take one through, so a mix task can build and deliver a fresh copy each run.

## Uses beyond manual testing

1. A golden test of the resolver: which questions the package produces (kinds, sections, firm or best guess).
2. An end-to-end walk through the review: answer every card, approve, check the Facts written.
3. An example of the import contract next to `priv/import/examples`.
4. A demo for other curators on preview.

As a test control it must bring its own catalog state (a test setup creating the plants, Galls and Sources each scenario needs, as the import fixtures do); the dev version uses real names in `gallformers_taxogall` that behave the right way, adding nothing fake.

## Why not now

Upkeep: the package changes with the contract's format; a golden test churns with every deliberate resolver change (five `c8c3` items in one week would each have changed it); an end-to-end walk breaks with every review UI change; the dev version's real names can drift with taxonomy edits; each new kind of question needs a scenario. All of that is heaviest while the review and the back end move daily.

## When to revisit

Once the review and the back end settle (around cutover). Then: the dev demo first (a script, no expectations to keep), and a golden test that checks only coarse things (each scenario produces its kind of question; approving writes Facts), the end-to-end walk once the UI stops moving. Estimates at the time: the dev demo an hour or two; test-grade about double; the walk-through on top.
