---
status: raw
created: 2026-10-06
updated: 2026-10-06
epic: taxonomy
relates: [8567]
needs: [294c, b119]
---

# Pipeline trial on existing Sources (go/no-go)

# Pipeline trial on existing Sources (go/no-go)

Step 3 of the reordered plan (`8567`, 2026-10-06). Needs the schema (`294c`) and the pipeline-vs-database diff (`b119`). **Decision point before the expensive work** (Sources–Facts, gall split).

Steps 1–3 of the migration approach in `b5bd` M2: run high-value existing Sources through the pipeline, compare with today's data, iterate until satisfied.

## Why

The real unknown is not code but **whether LLM output is good enough to be the input**. Adam is confident (frontier models, budget available); Jeff is unsure. The rest of the plan — pipeline-first admin, retiring forms, release after the backscan — rests on it, so get evidence first.

## Shape (2026-10-06)

- **Adam's pipeline produces the batches** against the schema, testing the contract with the party who will feed it.
- **6–10 existing Sources chosen for difficulty:** scanned text, keys, tables, a website, a correction — Sources whose content the database already holds.
- Diff each against today's database (`b119`) and inspect the disagreements.
- **Agree the pass criteria before running.** Candidates:
  - agreement with the database;
  - for each disagreement, whose error it is — the database's or the LLM's;
  - quote verification rate (quotes found in the plain text);
  - validator pass rate;
  - cost per Source;
  - curator effort to review a batch using the delta view.

- **Phase 0 format check** (`e381` v3 decision 11): run Docling on 2–3 of the Sources (born-digital and scanned) and judge whether DoclingDocument output is good enough as the structured document; if not on old scans, fall back to a minimal JSON block list.

## Outcomes

- **Go:** proceed to Sources–Facts (the taxonomy facade, `36ca`, first if not already done); the backscan becomes a run rather than weeks of work.
- **No-go:** rethink the pipeline-first premise before building on it.

## To work through

- The pass criteria and thresholds — with Adam?
- Choosing the Sources.
- What no-go means in practice (keep forms? a narrower pipeline?).

