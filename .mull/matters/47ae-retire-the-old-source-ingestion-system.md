---
status: raw
created: 2026-10-15
updated: 2026-10-15
epic: source-ingestion
---

# Retire the old source-ingestion system

The source-ingestion system built before the import contract (`294c`) is superseded by the contract, the producer in `services/import-producer/`, and the Gallformers-side importer (`e381`). Its plan matters (7fda, 7c67, fa48, 9314, 4fef, 7a83, db6f) were closed 2026-10-15. The code is still in the app and must be removed deliberately, not as a side effect of a cleanup.

## What exists (2026-10-15)

- **Python service** `services/source-ingestion/` (pipelines, prompts, schemas, tests; ~1.1 GB of ignored outputs, including the early POC's PDFs).
- **Elixir pipeline** `lib/gallformers/ingestion_pipeline/` (about 30 modules: Oban workflow and workers, stages, heuristics, an LLM client, a Python extractor that shells out to the service) and `lib/gallformers/ingestions.ex` with its schemas (`source_ingestion`, `source_ingestion_species`, `duplicate_candidate`).
- **Admin page** `/admin/ingestion-review` (`Admin.IngestionReviewLive`, superadmin only, PoC).
- **Database tables** from migration `20260421123000_add_source_ingestions.exs`.
- **Config** `:gallformers, :ingestion_pipeline` in `config/config.exs`.
- **Tests:** about 25 files under `test/gallformers/ingestion_pipeline/` and `test/gallformers/ingestions_test.exs`, plus fixtures.
- Possibly shared: `lib/gallformers/storage/source_artifacts.ex` and the source publisher (check before removing; the new importer may reuse storage).

## To decide before removing

- Whether anything in the Elixir pipeline is worth reusing for the importer (Oban workflow, duplicate detection by DOI/hash/MinHash, storage).
- Whether any rows exist in the source_ingestions tables in production.
- A migration that drops the tables.

