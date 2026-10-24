---
status: raw
created: 2026-10-06
updated: 2026-10-23
epic: taxonomy
relates: [8567, e381, 20e5]
blocks: [8546]
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

- **Open with Adam:** aphid generation values (e.g. stem mother/fundatrix vs apterae, as in Floate 2010), until an aphid Source needs them or Jeff and Adam supply the list; whether recorded occurrences keep coordinates as written (left out for now).
- **Vocabulary generator:** a mix task that writes the vocab files from the database, replacing the hand extraction.
- **Schema descriptions:** a pass to remove negative phrasing and consumer-side notes (producers read them too).
- **Golden regression set:** the five human-checked trial packages, re-run and diffed whenever the model or guide changes.

