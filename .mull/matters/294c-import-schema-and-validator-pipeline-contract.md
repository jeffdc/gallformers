---
status: raw
created: 2026-10-06
updated: 2026-10-15
epic: taxonomy
relates: [8567, e381, ca20, 20e5]
blocks: [b119, 8546]
---

# Import schema and validator (pipeline contract)

# Import schema and validator (pipeline contract)

The contract any producer follows to deliver a Source into Gallformers: format v3 (draft, no consumers yet). It lives in `priv/import/`; the decisions and their reasons are in `docs/import/producer-guide-background.md`. The Gallformers side is `e381`; the trial that tested it is `8546`.

## What exists (2026-10-15)

- `priv/import/PRODUCER_GUIDE.md` — the rules, organised by phase (1 Document … 6 Respond).
- `priv/import/VERIFY_GUIDE.md` — the phase 5 reviewer's rules.
- `priv/import/GALLFORMERS_STATEMENTS.md` — how Gallformers states its own Facts.
- `priv/import/schema/` — common, taxonomy, gall and review (phases 5–6) schemas.
- `priv/import/vocab/` — controlled lists, `places.json`, `traits.json` (definitions and mappings).
- `priv/import/examples/` — four complete packages.
- `priv/import/validate.py` — phase 4 checks and, with `--review`, the readiness gate; 74 tests in `priv/import/tests/`.

## Remaining work

- **Decisions with Adam:** season, detachable, recorded range, aphid generations, historical plant names, ID Notes (listed in the decisions doc). When decided, update `traits.json`, the guide and, for recorded range, the schema.
- **Season proposal** (for Adam). Sources report when a gall forms, when it is present on its host, and when the inducer emerges; the definition doesn't say which. Season is also an ID-tool filter ("when galls can be observed"; 193 galls tagged Winter, 33 only Winter). A) present on the host in the field (keeps the ID filter's meaning; rearing/emergence dates and galls found on the ground don't count); B) forms and grows (Winter only where the host grows then; the ID filter's meaning changes); C) both, as two traits. Recommended: A.
- **Vocabulary generator:** a mix task that writes the vocab files from the database, replacing the hand extraction.
- **Schema descriptions:** a pass to remove negative phrasing and consumer-side notes (producers read them too).
- **Golden regression set:** the five human-checked trial packages, re-run and diffed whenever the model or guide changes.

