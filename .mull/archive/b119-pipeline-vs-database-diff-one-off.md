---
status: done
created: 2026-10-06
updated: 2026-10-15
epic: taxonomy
relates: [8567, b5bd]
blocks: [8546]
needs: [294c]
---

# Pipeline-vs-database diff (one-off)

# Pipeline-vs-database diff (one-off)

Step 2 of the reordered plan (`8567`, 2026-10-06); steps 2 and possibly 6 of the migration approach in `b5bd` M2. Needs the schema (`294c`); used by the pipeline trial (`8546`).

## What it does (Jeff, 2026-10-06)

Takes the JSON the pipeline produced for a Source and compares it with the data stored today for the species that Source is mapped to (`species_source`) — **where the species is in both places**. The pipeline may produce more data than we have; how to treat that is a detail for when the tool is built. The question it answers: **how well do they align?**

- One-off, not part of the product. Elixir in the app (a mix task) reading today's tables directly.
- Today there are no Facts: the tool compares the pipeline's Facts with today's plain data (traits, hosts, ranges, aliases, descriptions) for that species.
- It may also serve step 6 — the whole-database sanity check after the bulk import — perhaps by running over all the JSON per species. Fuzzy for now; decide when building.

## To work through (when building)

- Name resolution: pipeline `name_as_written` vs today's names and aliases.
- What "align" means per kind (exact trait values, host sets, range differences, description passages).
- Output a human can read during the trial, with a judgement per difference of whose error it is — the database's or the LLM's.



**Closed 2026-10-15.** The pipeline trial built this comparison as an approximate dry run (`services/import-producer/scripts/dryrun.py`: name and Gall resolution against the dev database, and a Fact diff against the entries linked to the Source); results are in `8546`. A whole-database check after the bulk import, if wanted, belongs to the importer work (`e381`).
