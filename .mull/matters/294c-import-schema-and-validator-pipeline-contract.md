---
status: raw
created: 2026-10-06
updated: 2026-11-08
epic: taxonomy
relates: [8567, e381, 20e5, d213, c8c3, ca45]
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

## Step 3 (`50ff`): done 2026-10-27

**Decided (Jeff, 2026-10-27):**
- **Generation group mappings:**
  - heterogony → Cynipini;
  - seasonal → Cecidomyiidae and *Procecidochares*;
  - rust stages → Pucciniales;
  - aphid life cycle → Aphididae, Phylloxeridae and Adelgidae.
- **Pucciniales (B):** the taxonomy had no orders, and the ten rust families had no parent. Pucciniales is added as an order (kingdom Fungi) above the ten families: Coleosporiaceae, Cronartiaceae, Melampsoraceae, Phragmidiaceae, Pileolariaceae, Pucciniaceae, Pucciniastraceae, Raveneliaceae, Uropyxidaceae and Zaghouaniaceae.
- **Wording review:**
  - a generation stage that fits no value of its group goes to `unmapped`;
  - a multivoltine seasonal Gall takes `summer` only when its Inducer also induces a clearly different Gall in another season, and takes no generation when it is the Inducer's only Gall;
  - the four dropped negatives stay dropped.
- **Generation definitions:** best guesses for the seven missing ones, to be edited later.
- ***Besbicus*** moves under Cynipini, through a new curated `placements.csv`.
- **Golden regression set:** authorised and run (below). It runs again whenever the guide, prompt or model changes, and before the backscan (step 11).

**Built:**
- **Catalog migration.** Two new curated files in `priv/catalog_migration/`:
  - `added_taxa.csv`: the taxa Gallformers adds above today's taxonomy (Pucciniales, with its ten families placed under it through `Taxa.place/3`).
  - `generation_group_taxa.csv`: the 7 mappings, written in a new step 4 after Galls and resolved by accepted name and rank.

  - `placements.csv`: existing taxa moved to a new parent (*Besbicus* under Cynipini), checked by `Taxa.check_place/2` before the move.

  A row that doesn't resolve is a pending decision. On the production copy the strict run is clean (7 = 7 mappings; 10 families placed; 1 placement). There are 0 `generation_outside_groups` flags (*Besbicus* had 6), and id_parity shows 0 unexpected differences. Until now `generation_group_taxa` was always empty.
- **Vocabulary generator** (`Gallformers.Import.Vocab`, `mix gallformers.import.vocab`).
  - It writes every vocab file from the database and code; the prose lives in the generator.
  - `traits.json` gains `traits.generation.groups` and each generation value's `other_names`, and the `generation` enum grows to all 12 values.
  - A round-trip test holds the loader's seed and the generated file together until cutover. `Taxa.Rank` now holds its list in code, because the generator writes `ranks.schema.json` rather than reading it.
- **Guide.**
  - *Generations* in the producer guide: give a generation only for a clearly different Gall (multivoltine broods get none); a multivoltine seasonal Gall takes `summer` only beside another seasonal Gall of its Inducer; choose from the Inducer's group by definition.
  - A matching check in the verify guide, and the reasons in the background doc.
- **Wording pass.** 48 schema descriptions reworded, prose only. The before → after list is in `docs/plans/294c-wording-review.md` (local), with doubtful ones marked ⚑.
- **Golden set.** As above. 27 tests; scoring each trial package against its own golden file gives 195 of 195 present. Ashmead f141 counts as right, per Jeff's recount (2026-10-15).

- **Ligatures:** `NameNormalizer` (and the golden scorer) spell out æ and œ ("IMBRECARIÆ"), which NFKC leaves alone. The golden run found this.

**Verified:** `mix precommit` (2,495 tests), Dialyzer 0, the validator tests (89), the producer tests (91) and ruff, `--check` up to date, and a strict rehearsal on the production copy.

## First golden run (2026-10-27, authorised by Jeff)

The five trial Sources were rerun on the step 3 contract: phase 1 reused from the checked packages, then phases 2–6 and the dry run. It cost **$41.70** (Ashmead $9.58, 1862 $9.07, Floate $7.74, Nastasi & Davis $12.42, Aphis $2.87). All five packages pass `validate.py --review`. The runs are in `services/import-producer/output/golden-2026-10-27/` (local).

**Score: 177 of 195 golden items present.** Of the 184 judged right, 170 are present.

| Source | Present | Right, now missing or changed | Wrong |
|---|---|---|---|
| 98 Ashmead | 47 / 49 | 2 | — |
| 21 Osten Sacken 1862 | 40 / 45 | 3 | f118 fixed; f162 still present |
| 502 Floate | 38 / 41 | 2 | — |
| 680 Nastasi & Davis | 35 / 42 | 6 | — |
| 729 Aphis rubifolii | 17 / 18 | 1 | — |

**What the 14 right-but-missing items are:**
- **6 behaviour changes on Nastasi & Davis, for Jeff to rule on:**
  - The producer now sends the guide's whole "Unverified galls & hosts" section to `unmapped` instead of declaring its Galls: wood beauty stem gall, mossy bramble gall and silverpuff basal stem gall (5 items). Whether to import entries a Source marks unverified was left open in the trial.
  - It also no longer declares the off-hand intro Galls (mossy rose gall, hedgehog oak gall: 1 name match). This is the narrow "outside the Source's subject" rule from the trial, also left open.
- **2 season values** (Ashmead f260 Fall, Floate f51 Summer): expected from the new season definition ("forms and grows"), which also fixed 1862 f118.
- **3 small Trait omissions:** walls `thick`, `thin` and `ostiole`, each once.
- **1 rewording:** 1862 f62's description, at 0.58 similarity (threshold 0.6).
- **1 genus Host dropped** (Aphis f2 `Rubus host_of`): the Source names species Hosts, and the guide gives a genus Host only when it names no species.
- **1 name match** (Ashmead *Andricus imbrecariae*): the Source says "new species", so the batch now marks the Gall `new` and the dry run stops looking for an existing entry. Gallformers has it (*Kokkocynips imbricariae*). Importer question (`e381`): an old Source's "new species" may long exist; intake should still look for the entry.

**Working as intended:**
- Floate's aphid Galls now carry `fundatrix` and `apterae`.
- 1862's *C. q. palustris* gall is now `unmapped`, because the Source leaves its identity open (the name match was `unsure`).

**Contract question raised by the run:** on Nastasi & Davis, two *Antistrophus* Galls on whorled rosinweed (terminal and cryptic, both in the stem) share every `identified_by` field; only `form` tells them apart. The producer and reviewer agree that intake must key them by more than `identified_by`, or the contract needs another identifier.

## Open

- **Decided (Jeff, 2026-10-28):**
  - **Unverified entries are statements.** The authors publish them while saying they couldn't verify them personally. Named Galls are added as usual; unnamed ones become undescribed Galls. A later Source will likely describe them formally, and even if none does, holding the information is better than not. Hedges inside an entry still go to `unmapped`. This is in the producer guide and the background doc, and reverses the earlier "unverified = hedged" rule.
  - **Off-hand intro Galls stay out** (the rule the run already follows).
  - **Galls whose identifying fields are equal** (the rosinweed case; `identified_by` = Inducer, generation, Host, plant part): **a curator decision for now, no tiers yet.**
    - Two Galls can differ only by Traits, and any Trait might be the one that tells them apart. A tiered approach (tier 1 the identifying fields, tier 2 one or more Traits) is the likely answer, but we measure how often this occurs first.
    - Intake lists the possible entries and an admin picks. `GallMatcher` already did this when several catalog Galls match. It now also does so when two of a batch's Galls resolve to the same entry (2026-10-28), instead of silently merging them.
    - If it becomes a continual problem, solve it in code: Trait tiers in `identified_by`, with either the catalog Gall's current Trait Facts or identifying Traits stored on the Gall (like name parts) to match against.
    - Count it from the `ambiguous_match` queue items with the reason "the entry matches another of this batch's Galls too".
- **Importer (`e381`):** an old Source's "new species" still needs matching to an existing entry.
- **A 15-second connection warning, once:** during one rehearsal a process other than the migration timed out on a database connection while `host_range` was being re-keyed. It did not recur on a clean rerun. Watch for it at the rehearsal step (step 12).
- **Deferred (Jeff, 2026-10-27):** whether recorded occurrences keep coordinates as written when a Source prints them. Left out of the schema; revisit after release.
- **Gallformers notes as documents** (`20e5`, 2026-10-24; needed when notes are processed, after release):
  - a Gallformers batch may quote a document (the Gall's note) instead of only carrying statement text, and the validator checks those quotes;
  - a section in `GALLFORMERS_STATEMENTS.md` on reading notes: commentary, ID tips and links go to `unmapped`; copied passages are cited to their paper.
- **Small:** the mix tasks' `start_repo/0` helper now exists in three copies (`id_parity`, `export_legacy_trait_ids`, `import.vocab`).
