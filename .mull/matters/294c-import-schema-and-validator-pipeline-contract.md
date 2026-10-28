---
status: raw
created: 2026-10-06
updated: 2026-10-27
epic: taxonomy
relates: [8567, e381, 20e5]
---

# Import schema and validator (pipeline contract)

# Import schema and validator (pipeline contract)

The contract any producer follows to deliver a Source into Gallformers: format v3 (draft, no consumers yet). It lives in `priv/import/`; the decisions and their reasons are in `docs/import/producer-guide-background.md`. The Gallformers side is `e381`; the trial that tested it is `8546`.

## What exists (2026-10-27)

- `priv/import/PRODUCER_GUIDE.md` — the rules, organised by phase (1 Document … 6 Respond), including *Generations* (Phase 3).
- `priv/import/VERIFY_GUIDE.md` — the phase 5 reviewer's rules.
- `priv/import/GALLFORMERS_STATEMENTS.md` — how Gallformers states its own Facts.
- `priv/import/schema/` — the common, taxonomy, gall and review (phases 5–6) schemas.
- `priv/import/vocab/` — controlled lists, `places.json` and `traits.json` (definitions, mappings and generation groups). These are generated from the database by `mix gallformers.import.vocab`; `--check` fails when the committed files differ.
- `priv/import/examples/` — four complete packages.
- `priv/import/validate.py` — the phase 4 checks and, with `--review`, the readiness gate. 89 tests in `priv/import/tests/`.
- `services/import-producer/golden/` — the golden regression set: Jeff's 177 human-checked statements and 18 name matches from the five trial Sources. `produce golden score <run-dir>` reports, for each one, whether a new run kept it, changed it or lost it.

## Decided with Adam (2026-10-17)

These are applied to the contract and recorded in the decisions doc:
- **Season:** when the Gall forms and grows.
- **Detachable:** single-valued; `both` means ambiguous.
- **Recorded occurrences:** a new `occurrence` Fact kind in the gall batch.
- **Unresolved Host names:** resolved in a step before the import (`d585`).
- **Gallformers ID Notes:** no look-alikes concept; Facts are kept separate from commentary (`20e5`).

## Step 3 (`50ff`): built 2026-10-27, uncommitted

**Decided (Jeff, 2026-10-27):**
- **Generation group mappings:**
  - heterogony → Cynipini;
  - seasonal → Cecidomyiidae and *Procecidochares*;
  - rust stages → Pucciniales;
  - aphid life cycle → Aphididae, Phylloxeridae and Adelgidae.
- **Pucciniales (B):** the taxonomy had no orders, and the ten rust families had no parent. Pucciniales is added as an order (kingdom Fungi) above the ten families: Coleosporiaceae, Cronartiaceae, Melampsoraceae, Phragmidiaceae, Pileolariaceae, Pucciniaceae, Pucciniastraceae, Raveneliaceae, Uropyxidaceae and Zaghouaniaceae.
- **Wording pass:** Jeff reviews the diff before it is final.
- **Golden regression set:** one paid run of the five Sources follows, once Jeff has reviewed the wording and authorised the run, before the backscan (step 11). After that it runs whenever the guide, prompt or model changes.

**Built:**
- **Catalog migration.** Two new curated files in `priv/catalog_migration/`:
  - `added_taxa.csv`: the taxa Gallformers adds above today's taxonomy (Pucciniales, with its ten families placed under it through `Taxa.place/3`).
  - `generation_group_taxa.csv`: the 7 mappings, written in a new step 4 after Galls and resolved by accepted name and rank.

  A row that doesn't resolve is a pending decision. On the production copy the strict run is clean (7 = 7 mappings; 10 families placed), and id_parity shows 0 unexpected differences. Until now `generation_group_taxa` was always empty.
- **Vocabulary generator** (`Gallformers.Import.Vocab`, `mix gallformers.import.vocab`).
  - It writes every vocab file from the database and code; the prose lives in the generator.
  - `traits.json` gains `traits.generation.groups` and each generation value's `other_names`, and the `generation` enum grows to all 12 values.
  - A round-trip test holds the loader's seed and the generated file together until cutover. `Taxa.Rank` now holds its list in code, because the generator writes `ranks.schema.json` rather than reading it.
- **Guide.**
  - *Generations* in the producer guide: give a generation only for a clearly different Gall (multivoltine broods get none); a multivoltine seasonal Gall takes `summer`; choose from the Inducer's group by definition.
  - A matching check in the verify guide, and the reasons in the background doc.
- **Wording pass.** 48 schema descriptions reworded, prose only. The before → after list is in `docs/plans/294c-wording-review.md` (local), with doubtful ones marked ⚑.
- **Golden set.** As above. 27 tests; scoring each trial package against its own golden file gives 195 of 195 present. Ashmead f141 counts as right, per Jeff's recount (2026-10-15).

**Verified:** `mix precommit` (2,484 tests), Dialyzer 0, the validator tests (89), the producer tests (90) and ruff, `--check` up to date, and a strict rehearsal on the production copy.

## Open

- **Wording review (Jeff):** the ⚑ items in `docs/plans/294c-wording-review.md`:
  - a stage that fits no value of its group goes to `unmapped`;
  - the multivoltine `summer` rule has no condition: should a seasonal Gall that is its Inducer's only Gall take `summer`, or no generation?
  - four dropped negatives: "Omission is never denial", "not the PDF page index", "Nothing widens the range", and "Never because a name failed to resolve";
  - the generator's prose in `Gallformers.Import.Vocab`, including the season "about", which keeps its negative.
- **Definitions missing** for seven generation values: agamic, sexual, spring, summer, autumn, aecial and telial. The guide says to choose by definition (Jeff and Adam).
- **Six *Besbicus* Galls are flagged** `generation_outside_groups` (5 agamic, 1 sexual): *Besbicus* sits under Cynipidae, not Cynipini, so no group applies. Moving it under Cynipini clears them (decision: Jeff).
- **A 15-second connection warning, once:** during one rehearsal a process other than the migration timed out on a database connection while `host_range` was being re-keyed. It did not recur on a clean rerun. Watch for it at the rehearsal step (step 12).
- **The paid golden run:** after the wording review, with Jeff's authorisation for that run.
- **Deferred (Jeff, 2026-10-27):** whether recorded occurrences keep coordinates as written when a Source prints them. Left out of the schema; revisit after release.
- **Gallformers notes as documents** (`20e5`, 2026-10-24; needed when notes are processed, after release):
  - a Gallformers batch may quote a document (the Gall's note) instead of only carrying statement text, and the validator checks those quotes;
  - a section in `GALLFORMERS_STATEMENTS.md` on reading notes: commentary, ID tips and links go to `unmapped`; copied passages are cited to their paper.
- **Small:** the mix tasks' `start_repo/0` helper now exists in three copies (`id_parity`, `export_legacy_trait_ids`, `import.vocab`).

