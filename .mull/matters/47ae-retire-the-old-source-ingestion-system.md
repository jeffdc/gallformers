---
status: active
created: 2026-10-15
updated: 2026-10-23
epic: source-ingestion
relates: [e381, 9380]
---

# Retire the old source-ingestion system

The source-ingestion system built before the import contract (`294c`) is superseded by the contract, the producer in `services/import-producer/`, and the Gallformers-side importer (`e381`). Its plan matters (7fda, 7c67, fa48, 9314, 4fef, 7a83, db6f) were closed 2026-10-15. The code is still in the app and must be removed deliberately, not as a side effect of a cleanup.

Moved from the `taxogall` branch to main on 2026-10-23. The removal is done on its own branch off main (`retire-old-source-ingestion`), ahead of `9380` (Nix / toolchain alignment), because removing it takes Python out of the prod image.

## What exists (verified on main 2026-10-23)

- **Python service** `services/source-ingestion/` (pipelines, prompts, schemas, tests; ~1.1 GB of ignored outputs, including the early POC's PDFs).
- **Elixir pipeline** `lib/gallformers/ingestion_pipeline/` (about 30 modules: Oban workflow and workers, stages, heuristics, an LLM client, a Python extractor) and `lib/gallformers/ingestions.ex` with its schemas (`source_ingestion`, `source_ingestion_species`, `duplicate_candidate`).
- **Python extractor in the release:** `python_extractor.ex` runs `priv/python/pdf_text_extractor.py` (dependency `pymupdf4llm`), vendored into the release by `pip install --target` in both `Dockerfile` and `Dockerfile.preview`. This is the only reason the prod image installs `python3` / `py3-pip`. It does not call `services/source-ingestion/`.
- **Source publishing:** `lib/gallformers/source_publisher.ex` and `lib/gallformers/storage/source_artifacts.ex`. Only ingestion code uses them. The `:source_storage` config in `config/config.exs` is read only by `SourceArtifacts`.
- **Admin page** `/admin/ingestion-review` (`Admin.IngestionReviewLive`, superadmin only, PoC): route at `router.ex:154`, dashboard link at `dashboard_live.ex:184`.
- **Database tables** `source_ingestions`, `source_ingestion_duplicate_candidates`, `source_ingestion_species` from migration `20260421123000_add_source_ingestions.exs`.
- **Config:** `:gallformers, :ingestion_pipeline` (DeepInfra models/URL) and the Oban `extraction` queue in `config/config.exs`.
- **Prompts and schema** `priv/prompts/` (`data_extract.txt`, `llm_clean.txt`, `metadata.txt`) and `priv/schemas/gall_record.json` — added with the pipeline; found during the removal, not in the original inventory.
- **Dependency:** `ex_json_schema` in `mix.exs` — used only by `IngestionPipeline.Schema`.
- **Tests:** `test/gallformers/ingestion_pipeline/` (~25 files), `ingestions_test.exs`, `source_publisher_test.exs`, `storage/source_artifacts_test.exs`, `test/gallformers_web/live/admin/ingestion_review_live_test.exs`, `test/support/fixtures/ingestion_pipeline_fixtures.ex`.
- **Small leftovers:** `.gitignore` `/priv/storage/` entry ("Local source-ingestion artifacts and uploaded PDFs"); `Gallformers.Storage` moduledoc mentions `SourceArtifacts`; `infra/s3.tf` comment on the `gallformers-private` bucket describes source-ingestion use.
- **S3:** objects under `s3://gallformers-private/source-ingestions/`. The bucket itself stays — `e381` delivers import batches to the private bucket.

## Decisions (2026-10-23)

- **Reuse nothing.** Delete all of it. `e381` is designed fresh. If something (e.g. DOI/hash/MinHash duplicate detection) is wanted later, retrieve it from git — the removal commit is recorded below.
- **Prod data:** checked against a fresh local copy of prod (latest Oban job 2026-10-23 07:00): all three tables have **0 rows**, and there are **no** Oban jobs for `Gallformers.IngestionPipeline.*` workers or the `extraction` queue. Nothing to preserve or cancel. The daily full backups in S3 hold the (empty) tables anyway.
- **Drop the tables in the same PR** as the code removal. `down/0` is a no-op (repo convention for destructive migrations).
- **Remove `ex_json_schema`.** Unused after the removal. If `e381`'s importer needs JSON Schema validation it re-adds a library that supports the schema draft `priv/import/` uses (to check: `ex_json_schema` only covers up to draft 7).
- **Remove `:source_storage` config.** Only `SourceArtifacts` reads it. The importer will add its own config when it exists.
- **Python leaves the prod image.** Drop `python3` / `py3-pip` and the vendoring step from both Dockerfiles. Recommendation for `e381`: keep the server-side importer pure Elixir so Python never returns to the image.

## Plan

One branch, one PR.

1. **Delete code and tests:** everything listed under "What exists" for the Elixir pipeline, ingestions context, source publishing, admin page, fixtures and tests; `priv/python/`; `services/source-ingestion/` (tracked files only).
2. **Unwire:** router line, dashboard link, `:ingestion_pipeline` + `:source_storage` config, Oban `extraction` queue, `ex_json_schema` dep (+ `mix deps.unlock --unused`), `Storage` moduledoc.
3. **Migration** `priv/repo/migrations/<ts>_drop_source_ingestions.exs`: drop `source_ingestion_species`, `source_ingestion_duplicate_candidates`, then `source_ingestions`; `down/0` no-op with a moduledoc saying why.
4. **Dockerfiles:** remove Python from builder and runtime stages and the `pip install --target` step in `Dockerfile` and `Dockerfile.preview`. Verify with a local `docker build` of both (native arch is enough to prove the build; prod is linux/amd64).
5. **Leftovers:** `.gitignore` `/priv/storage/` entry (confirm nothing else writes there first), `infra/s3.tf` bucket comment (comment only — no `tofu apply` needed).
6. **Verify:** `mix compile --warnings-as-errors`, `mix precommit`, `make test` (test DB rebuild runs the new migration), `mix ecto.migrate` against the local prod copy, dev server loads `/admin` without the link.

## Progress (2026-10-23)

- All plan steps done on branch `retire-old-source-ingestion`, including `priv/prompts/` and `priv/schemas/`. Merged to main as PR #594, **removal commit `a03a74dc`** (retrieve removed code with `git show a03a74dc^:<path>`).
- Both images build locally (native arm64): `Dockerfile` and `Dockerfile.preview`; the prod image has no `python3`, Typst 0.14.2 works.
- Python lines in both Dockerfiles were added only by `4127a877` (the extractor commit); removal restores the pre-extractor lines.
- Verified: `mix compile --warnings-as-errors`, `mix precommit` (1932 tests, 0 failures), migration run against the local prod copy, `make test-db`.

## After merge (Jeff)

- Delete ignored leftovers on disk: `priv/python/` (`.venv`, egg-info), `priv/storage/dev/` (now untracked since its `.gitignore` entry was removed).

- Delete the ignored outputs left on disk in `services/source-ingestion/` (~1.1 GB).
- Optionally delete `s3://gallformers-private/source-ingestions/`.
- Close the Dependabot branches for `services/source-ingestion` (`origin/dependabot/uv/services/source-ingestion/*`, `origin/chore/python-deps-update` if it only touched that service) and remove that directory from Dependabot's config if it's set in GitHub settings.
- When `taxogall` next merges main, take main's version of this matter (it was added on both branches).
