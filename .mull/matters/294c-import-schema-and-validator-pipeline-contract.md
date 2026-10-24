---
status: raw
created: 2026-10-06
updated: 2026-10-24
epic: taxonomy
relates: [8567, e381, 20e5]
---

# Import schema and validator (pipeline contract)

# Import schema and validator (pipeline contract)

The contract any producer follows to deliver a Source into Gallformers: format v3 (draft, no consumers yet). It lives in `priv/import/`; the decisions and their reasons are in `docs/import/producer-guide-background.md`. The Gallformers side is `e381`; the trial that tested it is `8546`.

## What exists (2026-10-23)

- `priv/import/PRODUCER_GUIDE.md` — the rules, organised by phase (1 Document … 6 Respond).
- `priv/import/VERIFY_GUIDE.md` — the phase 5 reviewer's rules.
- `priv/import/GALLFORMERS_STATEMENTS.md` — how Gallformers states its own Facts.
- `priv/import/schema/` — common, taxonomy, gall and review (phases 5–6) schemas.
- `priv/import/vocab/` — controlled lists, `places.json`, `traits.json` (definitions and mappings).
- `priv/import/examples/` — four complete packages.
- `priv/import/validate.py` — phase 4 checks and, with `--review`, the readiness gate; 82 tests in `priv/import/tests/`.

## Decided with Adam (2026-10-17)

Applied to the contract and recorded in the decisions doc: season (when the Gall forms and grows), detachable (`both` means ambiguous; single-valued), recorded occurrences (new `occurrence` Fact kind in the gall batch), unresolved Host names (a precursor step of import, `d585`), Gallformers ID Notes (no look-alikes concept; Facts vs commentary, `20e5`).

## Remaining work

- **Generation groups** (`8567`, *Generation groups*): generation values come in groups mapped to taxa. When the groups are settled, `traits.json` lists each group's values, definitions and taxa, and the guide tells producers to choose from the group for the Inducer's taxon and to give a generation only when the Source shows a clearly different Gall (repeated broods that induce the same Gall are multivoltine). Aphid values chosen in `8567`; the provisional `generation` enum in `vocab/traits.schema.json` grows to match.
- **Open with Adam:** whether recorded occurrences keep coordinates as written (left out for now).
- **Vocabulary generator:** a mix task that writes the vocab files from the database, replacing the hand extraction.
- **Schema descriptions:** a pass to remove negative phrasing and consumer-side notes (producers read them too).
- **Golden regression set:** the five human-checked trial packages, re-run and diffed whenever the model or guide changes.
- **Gallformers notes as documents** (`20e5`, 2026-10-24; needed when notes are processed, after release): a Gallformers batch may quote a document (the Gall's note) instead of only carrying statement text, and the validator checks those quotes; a section in `GALLFORMERS_STATEMENTS.md` on reading notes (commentary, ID tips and links to `unmapped`; copied passages cited to their paper).
