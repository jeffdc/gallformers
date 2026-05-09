---
status: done
created: 2026-04-21
updated: 2026-05-08
epic: ingestion
relates: [fa48]
blocks: [7fda]
parent: 7fda
---

# Persisted source ingestion review queue and detail workflow

## Execution Plan: Persisted Source Ingestion Review Workflow

Implement `7c67` as a phased replacement of the current superadmin-only ingestion-review PoC with a DB-backed workflow that uses the persisted ingestion state already present in the repo. This matter includes both the new reviewer-facing ingestion creation entrypoint for `pdf`, `url`, and `text`, and the full persisted review workflow: queue, duplicate review, source resolution, gall review, and completion.

This plan is implementation-complete. An agent should be able to execute it without making product decisions.

### Locked Assumptions For This Matter

- Keep auth and routing scope superadmin-only for now.
- Replace the current `/admin/ingestion-review` PoC in place.
- Add `/admin/ingestion-review/:id` as the canonical persisted detail page.
- Split the web implementation into two LiveViews:
  - `GallformersWeb.Admin.IngestionReviewLive.Index` for the queue and submission page
  - `GallformersWeb.Admin.IngestionReviewLive.Show` for the detail/review page
- Support `pdf`, `url`, and `text` submission in this matter. `docx` remains deferred.
- Duplicate review V1 supports `confirm duplicate`, `reject candidate`, and `promote to unique` by rejecting all pending candidates. It does not support making the new ingestion the canonical root instead.
- Use persisted review state in Postgres. Do not preserve the local `services/source-ingestion/output/...` workflow as a compatibility layer.
- Inline creation of `source` rows is not part of this matter. The detail page links to the existing `/admin/sources/new` flow and then allows association after return.
- Phase 5 persists reviewer decisions onto `source_ingestion_species` only. It does not create or mutate real domain data such as `species_source`, gall traits, host associations, aliases, or new species records.

### Existing Code To Replace

Current PoC code that should be removed or retired by the end of this matter:
- `lib/gallformers_web/live/admin/ingestion_review_live.ex`
- `test/gallformers_web/live/admin/ingestion_review_live_test.exs`
- the current `/admin/ingestion-review` route that points at the PoC module

Persisted backend already available and must be reused, not redesigned:
- `Gallformers.Ingestions`
- `Gallformers.IngestionPipeline.Worker`
- `Gallformers.IngestionPipeline.DuplicateResolution`
- `Gallformers.IngestionPipeline.Workflow`
- `source_ingestions`
- `source_ingestion_duplicate_candidates`
- `source_ingestion_species`

Known backend gap that this matter must close:
- `pdf` is truly supported today, but the current extract stage is still PDF-only. `url` and `text` submission must become first-class pipeline inputs before the frontend can honestly ship.

### Required Workflow For Every Phase

For each phase, in order:
1. Read the phase and inspect the relevant code paths before writing.
2. Write tests first. If it does not make sense to write a test, or the only path forward requires brittle mocking or untestable UI tricks, stop and engage the human.
3. Implement the code.
4. Run `mix compile --warnings-as-errors`.
5. Run the phase’s target tests.
6. Run `mix precommit` and fix issues until it is green.
7. Stop and review with the human before starting the next phase.
8. Append completed work, implementation decisions, and deviations to `7c67`.

At matter completion:
- Append a final summary of shipped behavior and deferred follow-ups.
- Mark `7c67` done only after the final phase is green and the human agrees.

## Phase 1: Submission Plumbing And Queue Read Model

### Goal

Create the backend needed for a real persisted queue and real creation flow. After this phase, the system must be able to create ingestions for `pdf`, `url`, and `text`, store the initial artifact, and enqueue the pipeline using the existing worker.

### Required Implementation

1. Add one new public submission API to `Gallformers.Ingestions`.
- Name: `submit_source_ingestion/1`
- Input shape:
  - `%{input_type: "pdf", uploaded_by_id: user_id, filename: filename, content: binary}`
  - `%{input_type: "url", uploaded_by_id: user_id, url: url}`
  - `%{input_type: "text", uploaded_by_id: user_id, text: text}`
- Behavior:
  - validate required keys per input type
  - call `create_source_ingestion/1` for the row itself
  - upload the initial input artifact under the ingestion prefix
  - enqueue `Gallformers.IngestionPipeline.Worker`
  - if artifact upload or enqueue fails, return an error and clean up any created artifact keys for that ingestion
- Artifact keys are fixed and not configurable:
  - `pdf` -> `input/source.pdf`
  - `url` -> `input/source.url`
  - `text` -> `input/source.txt`

2. Add one queue query API to `Gallformers.Ingestions`.
- Name: `list_source_ingestion_queue_rows/1`
- Return one row struct or map per ingestion, ordered newest-first.
- Required fields in each row:
  - `id`
  - `title`
  - `display_title`
  - `input_type`
  - `status`
  - `processing_stage`
  - `inserted_at`
  - `uploaded_by_id`
  - `uploaded_by_name`
  - `source_id`
  - `duplicate_of_source_ingestion_id`
  - `pending_duplicate_candidates_count`
  - `total_duplicate_candidates_count`
  - `total_species_entries_count`
  - `pending_species_entries_count`
  - `resolved_species_entries_count`
- Supported filters in the opts keyword list:
  - `:status` for one or many statuses
  - `:uploaded_by_id`
  - `:include_complete` boolean
- `display_title` fallback order is fixed:
  1. `title` if present and non-blank
  2. `"Untitled URL submission"` for url submissions with no extracted title
  3. `"Untitled text submission"` for text submissions with no extracted title
  4. `"Untitled PDF submission"` for pdf submissions with no extracted title

3. Add one queue summary helper to `Gallformers.Ingestions`.
- Name: `queue_status_label/1`
- This returns the UI-facing summary string so status wording stays out of LiveView.
- Fixed label rules:
  - `needs_duplicate_review` -> `"Needs duplicate review"`
  - `needs_review` with zero pending species entries and zero total species entries -> `"Needs source review"`
  - `needs_review` with source missing -> `"Needs source review"`
  - `needs_review` with pending species entries > 0 -> `"X of Y galls remaining"`
  - `complete` -> `"Complete"`
  - `duplicate_confirmed` -> `"Duplicate confirmed"`
  - `failed` -> `"Failed at <stage>"`
  - all other processing states -> `"Processing: <stage>"`

4. Extend extract-stage support.
- `lib/gallformers/ingestion_pipeline/stages/extract.ex` remains the first runnable stage.
- Required behavior by `input_type`:
  - `pdf`: preserve current flow exactly
  - `text`: download `input/source.txt`, upload same bytes to `extract/text.txt`, transition `:extract_succeeded`
  - `url`: download `input/source.url`, hand URL to a new extractor adapter, upload extracted text to `extract/text.txt`, transition `:extract_succeeded`
- Add a new adapter module pair:
  - behaviour: `Gallformers.IngestionPipeline.Stages.Extract.URLExtractor`
  - default implementation: `Gallformers.IngestionPipeline.Stages.Extract.TrafilaturaURLExtractor` or equivalent repo-appropriate naming
- The adapter returns `{:ok, %{text: text}} | {:error, reason}`.
- Do not change `Workflow` state names or transitions.

5. Extend fixture support for later phases.
- Expand `test/support/fixtures/ingestion_pipeline_fixtures.ex` to include helpers for:
  - duplicate candidates with evidence maps
  - review-ready ingestions with `source_id`
  - ingestions with species entries ordered by `position`
  - ingestion species entries with realistic `extraction_payload` for hosts, traits, and description evidence

### Constraints

- Do not redesign status names, stage names, or duplicate semantics.
- Do not add new tables.
- Do not add UI in this phase beyond what is required for tests of the backend APIs.
- Keep all queue aggregation logic in `Gallformers.Ingestions`, not in LiveView.

### Tests

Primary test files for this phase:
- `test/gallformers/ingestions_test.exs`
- `test/gallformers/ingestion_pipeline/full_pipeline_test.exs`
- add one focused extract-stage test file if existing files become too overloaded

Required coverage:
- `submit_source_ingestion/1` for `pdf`, `url`, `text`
- artifact path correctness per input type
- cleanup behavior when enqueue fails
- extract stage success for `pdf`, `url`, `text`
- extract-stage failure behavior for invalid or fetch-failed URL input
- queue row aggregation and ordering
- queue label helper behavior across mixed states

## Phase 2: Replace Landing Page With Persisted Queue And New Source Entry

### Goal

Replace the current PoC landing page with a queue page backed entirely by persisted ingestion state, and include the new `New Source` entrypoint on that page.

### Required Implementation

1. Replace the PoC LiveView with `GallformersWeb.Admin.IngestionReviewLive.Index`.
- Router target for `/admin/ingestion-review` must point to this new module.
- Remove all dependencies on upload hash query params, local output dir loading, `Task.start` shelling to `uv`, fake `handle_info` loading patterns, and local markdown editing.
- The new queue page loads exclusively from `list_source_ingestion_queue_rows/1`.

2. Use existing reusable components only.
- Queue table must use the existing table component, not a custom table.
- Submission controls must use existing form components, including the existing dropzone for PDF upload.
- Search and filter fields must use existing admin form/search helpers where possible.

3. Queue page state and filters.
- Assigns must include:
  - queue rows
  - `include_complete` boolean default `false`
  - `uploaded_by_scope` with default `:me`
  - per-input submission form state for `pdf`, `url`, and `text`
- Fixed uploader filter behavior:
  - `:me` means current user id if present
  - `:all` means no uploader filter
- If current user id cannot be resolved, default uploader scope falls back to `:all`.

4. Queue table columns and labels.
- Table columns are fixed:
  - Title
  - Species
  - Status
  - Uploaded
  - By
- Species column display rules:
  - if `total_species_entries_count > 0`, show `"<resolved> of <total> reviewed"`
  - else show `"No extracted galls yet"`
- Status column must call `queue_status_label/1`.
- Duplicate-review rows must render a visible badge using existing badge components.

5. Submission UX.
- Provide three submission modes on the page:
  - PDF upload
  - URL input
  - Text textarea
- After successful submit, redirect immediately to `/admin/ingestion-review/:id`.
- On error, remain on the queue page and surface the validation or pipeline-enqueue error.
- Do not keep any background-progress UI on this page.

### Constraints

- No custom inline dropzone or bespoke table component.
- No local file system inspection from LiveView.
- No raw Repo queries in web code.
- Do not combine queue and detail behaviors in one large LiveView.

### Tests

Primary test file for this phase:
- replace `test/gallformers_web/live/admin/ingestion_review_live_test.exs` with `test/gallformers_web/live/admin/ingestion_review_live/index_test.exs`

Required coverage:
- persisted rows render
- default filter hides complete items
- uploader filter behavior for `me` and `all`
- duplicate-review rows render a distinct badge
- submission success for `pdf`, `url`, `text`
- submission failure stays on page and shows an error
- row navigation goes to `/admin/ingestion-review/:id`

## Phase 3: Persisted Detail Page With Duplicate Review Gate

### Goal

Implement the real detail page and make duplicate resolution the first blocking gate before source or gall review is allowed.

### Required Implementation

1. Add `GallformersWeb.Admin.IngestionReviewLive.Show`.
- Router target for `/admin/ingestion-review/:id` must point to this module.
- Load the page exclusively through `get_source_ingestion_with_details!/1`.
- Subscribe to no local pipeline shell-out messages. All state comes from the database.

2. Add a detail-page view model helper in `Gallformers.Ingestions`.
- Name: `source_ingestion_review_view!/1`
- This helper wraps `get_source_ingestion_with_details!/1` and returns a struct or map containing exactly what the detail page needs:
  - ingestion core fields
  - duplicate candidates ordered for review
  - species entries ordered by `position`
  - booleans for `duplicate_review_required?`, `source_review_unlocked?`, `species_review_unlocked?`
  - summary counts used by the page header
- Keep page-shaping logic out of LiveView where practical.

3. Duplicate review section.
- Show one candidate card per `duplicate_candidate`.
- Each card renders:
  - candidate title or fallback title
  - candidate authors if present
  - candidate year if present
  - candidate status
  - evidence rows
- Evidence rows map fixed keys to fixed labels:
  - `normalized_doi` -> `DOI match`
  - `preprocessed_text_sha256` -> `Exact normalized text match`
  - `normalized_title` -> `Title match`
  - `title_fingerprint` -> `Title fingerprint match`
  - `author_fingerprint` -> `Author overlap`
  - `publication_year` -> `Year match`
  - `similarity` -> `Text similarity`
- Unknown evidence keys are ignored.

4. Duplicate-review actions.
- Event names are fixed:
  - `confirm_duplicate_candidate`
  - `reject_duplicate_candidate`
  - `promote_ingestion_to_unique`
- Action handlers must call only:
  - `DuplicateResolution.confirm_duplicate/2`
  - `DuplicateResolution.reject_duplicate/2`
  - `DuplicateResolution.promote_to_unique/2`
- After each action, reload the review view model from `source_ingestion_review_view!/1`.

5. Locking rules.
- While duplicate review is unresolved:
  - source mapping controls render disabled with explanatory text
  - gall list rows render disabled with explanatory text
  - no hidden escape path should allow workspace opening

### Constraints

- Do not implement canonical-ingestion swapping.
- Do not add new duplicate statuses.
- Do not duplicate duplicate-resolution business logic inside LiveView.

### Tests

Primary test file for this phase:
- `test/gallformers_web/live/admin/ingestion_review_live/show_duplicate_review_test.exs`

Required coverage:
- detail page renders duplicate-review candidates and evidence
- sparse evidence maps render safely
- confirm/reject/promote actions work
- source controls are locked while duplicate review is open
- gall review entry is locked while duplicate review is open

## Phase 4: Source Resolution And Persisted Gall List

### Goal

Implement the normal review detail page after duplicate disposition: source first, then the persisted list of gall review items.

### Required Implementation

1. Source metadata section.
- Render from `source_ingestions` fields only:
  - title
  - authors
  - publication year
  - DOI
- Do not read metadata from artifacts in the web layer.

2. Source resolution API surface.
- Use existing `Sources.search_sources/1` and `Sources.get_source!/1` for lookup.
- Use existing `Ingestions.associate_source/2` and `Ingestions.clear_source_association/1` for persistence.
- Do not create a second source-association API in the web layer.

3. Source resolution UI.
- Use existing `typeahead` component.
- Use these fixed events:
  - `search_sources`
  - `select_source`
  - `associate_source`
  - `clear_source_association`
- `select_source` updates transient page state only.
- `associate_source` is the explicit persistence step.
- Link to `/admin/sources/new` in a new tab for missing sources.

4. Gall/species list.
- Render directly from ordered `source_ingestion_species` rows.
- Each row must show:
  - `position`
  - `extracted_name`
  - `extracted_authority`
  - mapped species name if present
  - host count derived from `extraction_payload["hosts"]`
  - status
- Fixed host count behavior:
  - missing or invalid `hosts` payload -> count `0`
- Progress header must use persisted counts from the review view model.

5. Unlock behavior.
- No gall workspace entry until `source_id` is present.
- Once `source_id` is present, row action becomes available.

### Constraints

- Do not carry forward the PoC’s transient species-match state.
- Do not rebuild grouped gall logic from raw extraction blobs.
- Do not auto-associate a source merely because one was selected in typeahead.

### Tests

Primary test file for this phase:
- `test/gallformers_web/live/admin/ingestion_review_live/show_source_resolution_test.exs`

Required coverage:
- metadata rendering
- source typeahead search
- select vs associate distinction
- clear association
- gall list ordering and host counts
- lock/unlock before and after source association

## Phase 5: Gall Review Workspace And Persisted Review Decisions

### Goal

Implement the per-gall review workspace described by `fa48`, but back it strictly with persisted `source_ingestion_species` state. This phase captures reviewer decisions; it does not write them into the main taxonomy, gall, host, or species-source domain tables.

### Required Implementation

1. Add one context update API for the workspace.
- Name: `update_source_ingestion_species_review/3`
- Signature:
  - `update_source_ingestion_species_review(source_ingestion_species, attrs, reviewed_by_id)`
- This is the only workspace persistence API.
- It may internally call `transition_source_ingestion_species_status/3`, but LiveView must not hand-assemble review persistence through multiple calls.

2. Review payload shape is fixed.
- Persist reviewer decisions under `review_payload` with this structure:
  - `"species_review"`:
    - `"decision"`: `"mapped" | "skip"`
    - `"species_id"`: integer or null
    - `"notes"`: optional string
  - `"host_reviews"`: list of
    - `"extracted_name"`
    - `"extracted_authority"`
    - `"decision"`: `"mapped" | "unresolved" | "skip"`
    - `"species_id"`: integer or null
  - `"trait_reviews"`: map keyed by trait name where each value contains
    - `"selected_values"`: list of strings
    - `"raw_evidence"`: list of strings copied from extraction payload when saved
  - `"description_review"`:
    - `"edited"`: boolean
- Do not invent additional top-level keys unless a concrete implementation need appears and is discussed with the human.

3. Workspace shell and entry.
- Use an existing modal component.
- One workspace session edits exactly one `source_ingestion_species` row.
- Opening a row loads all data from the persisted row, not from queue assigns.

4. Species review section.
- Use existing species search APIs:
  - `Species.search_species_by_name/3`
  - `Species.find_species_with_alias/1`
  - `Species.get_species!/1`
- Decision options are fixed:
  - map to existing species
  - skip for later
- `created` status is not used in this matter because no new species are created here.

5. Host review section.
- Read hosts from `extraction_payload["hosts"]`.
- Use existing species search APIs with taxoncode `plant`.
- Persist host mapping decisions into `review_payload` only.
- Do not create or update real host associations in this matter.

6. Trait review section.
- Read traits from `extraction_payload["traits"]`.
- Use existing UI components and controlled-vocabulary patterns already used in gall admin forms where practical.
- Persist final selected values into `review_payload["trait_reviews"]`.
- Do not mutate real gall trait tables in this matter.

7. Description review section.
- Edit and persist `description_prose` directly on the `source_ingestion_species` row.
- Set `review_payload["description_review"]["edited"]` based on whether the saved prose differs from the loaded prose.

8. Status rules for this matter.
- Fixed meanings:
  - `pending`: untouched or unresolved
  - `mapped`: reviewer mapped the gall species and saved a structured review payload
  - `skipped`: reviewer explicitly deferred the row
  - `complete`: reviewer has finished the row and no further review is needed
- `created` is not used in this matter because new species creation is out of scope.
- A row may move to `complete` only if:
  - source is associated
  - species decision is `mapped`
  - host reviews contain no `unresolved` decisions
  - description has been reviewed
- Otherwise, saving a non-empty review moves the row to `mapped` or `skipped` according to the chosen action.

### Constraints

- Search before writing: inspect existing species-mapping and trait-review admin pages and borrow patterns instead of inventing them.
- Do not add custom inline UI widgets when existing components are sufficient.
- Do not write to `species_source`, gall traits, host links, aliases, or taxonomy tables in this phase.

### Tests

Primary test file for this phase:
- `test/gallformers_web/live/admin/ingestion_review_live/show_workspace_test.exs`

Required coverage:
- workspace render from persisted `source_ingestion_species`
- species mapping save into `species_id` and `review_payload`
- host mapping persistence in `review_payload`
- trait evidence render and save
- description editing persistence
- status transition rules
- workspace remains inaccessible when source is unassociated

## Phase 6: Completion Logic, Queue Finalization, And PoC Retirement

### Goal

Finish the workflow so completed review work leaves the active queue, and remove the remaining PoC assumptions from code and tests.

### Required Implementation

1. Add one orchestration helper in `Gallformers.Ingestions`.
- Name: `maybe_complete_source_ingestion_review/1`
- Behavior:
  - load the ingestion
  - if status is `needs_review`
  - and all species entries are resolved
  - then transition workflow via `:review_completed`
  - else return the ingestion unchanged
- This helper is called after every successful workspace save.

2. Define resolved-species-entry semantics for this matter.
- `pending` is unresolved.
- `mapped`, `skipped`, and `complete` are resolved.
- `created` is not expected in this matter but should still count as resolved if encountered.

3. Queue finalization behavior.
- Default queue filter hides `complete` rows.
- `duplicate_confirmed` rows are not shown in the default active queue unless the human later asks for a separate duplicate-history view.
- `failed` rows remain visible in the active queue.

4. PoC cleanup.
- Delete the old PoC LiveView module once routes and tests point to the new index/show modules.
- Delete or replace the PoC-only test file.
- Remove any leftover helper functions or assigns that reference local output directories, pipeline hashes, fake load messages, or shell-out pipeline execution.

5. Matter closeout.
- Append shipped phases, final behavior, and deferred follow-ups to `7c67`.
- Deferred follow-ups to record explicitly:
  - `docx` submission
  - canonical root promotion or swapping
  - dedicated ingestion reviewer role
  - inline source creation workflow
  - writing workspace review decisions into real domain tables in a later matter

### Tests

Primary test files for this phase:
- `test/gallformers/ingestions_test.exs`
- `test/gallformers_web/live/admin/ingestion_review_live/index_test.exs`
- `test/gallformers_web/live/admin/ingestion_review_live/show_completion_test.exs`

Required coverage:
- ingestion transitions to `complete` when all species entries are resolved
- completed items disappear from default queue view
- completed items appear when complete filter is enabled
- duplicate-confirmed rows are not treated as active review work
- end-to-end happy path from create ingestion through complete

## File-Level Execution Guidance

Use these file areas unless exploration during implementation reveals an existing better home:

Context and workflow changes:
- `lib/gallformers/ingestions.ex`
- `lib/gallformers/ingestion_pipeline/stages/extract.ex`
- add small focused modules under `lib/gallformers/ingestion_pipeline/stages/extract/` for the URL extractor abstraction
- `test/support/fixtures/ingestion_pipeline_fixtures.ex`

Web layer:
- `lib/gallformers_web/router.ex`
- `lib/gallformers_web/live/admin/ingestion_review_live/index.ex`
- `lib/gallformers_web/live/admin/ingestion_review_live/show.ex`

Tests:
- `test/gallformers/ingestions_test.exs`
- `test/gallformers/ingestion_pipeline/full_pipeline_test.exs`
- `test/gallformers_web/live/admin/ingestion_review_live/index_test.exs`
- `test/gallformers_web/live/admin/ingestion_review_live/show_duplicate_review_test.exs`
- `test/gallformers_web/live/admin/ingestion_review_live/show_source_resolution_test.exs`
- `test/gallformers_web/live/admin/ingestion_review_live/show_workspace_test.exs`
- `test/gallformers_web/live/admin/ingestion_review_live/show_completion_test.exs`

Do not treat this file list as permission to skip repo exploration. Search first for nearby existing patterns before editing.

## Acceptance Criteria

`7c67` is done when all of the following are true:
- reviewers can create persisted ingestions for `pdf`, `url`, and `text`
- `/admin/ingestion-review` is a persisted queue, not a PoC shell to local output
- `/admin/ingestion-review/:id` is the canonical detail page
- duplicate review is explicit and blocks normal review until resolved
- source association blocks gall review until resolved
- gall review runs off `source_ingestion_species` persisted state
- gall review decisions persist to `species_id`, `description_prose`, `status`, and `review_payload`
- ingestion completion is derived from resolved species entries
- all PoC-only local-output logic is removed from the admin workflow
- every phase was individually taken to green with `mix compile --warnings-as-errors` and `mix precommit`
- Mull contains the final implementation record for the matter

## Deferred Follow-Ups

- `docx` submission
- canonical-ingestion replacement or root swapping
- dedicated ingestion reviewer role
- inline source creation workflow
- applying persisted review decisions into real domain tables

## Assumptions

- The existing ingestion schema and workflow are the canonical model for this matter.
- URL extraction can be implemented behind a new adapter without changing the outer workflow semantics.
- Inline creation of real `source` records is out of scope for `7c67`; linking to existing source admin is sufficient.
- Review payload persistence on `source_ingestion_species.review_payload` is acceptable for host and trait reviewer decisions in V1.
- The current route remains superadmin-only until a later auth-focused matter changes that.

Phase 1 completed on 2026-05-01.

- Added `Gallformers.Ingestions.submit_source_ingestion/1` for `pdf`, `url`, and `text` submissions. It validates per-input attrs, creates the persisted ingestion row, uploads the canonical `input/source.*` artifact, enqueues the existing Oban worker, and cleans up private artifacts when upload/enqueue fails.
- Added `Gallformers.Ingestions.list_source_ingestion_queue_rows/1` with newest-first ordering, uploader/status filters, complete-item filtering, duplicate/species aggregate counts, uploader display-name projection, and `display_title` fallback rules.
- Added `Gallformers.Ingestions.queue_status_label/1` so queue status wording stays in the backend.
- Extended `Gallformers.IngestionPipeline.Stages.Extract` to support `text` submissions by copying `input/source.txt` to `extract/text.txt`, and `url` submissions by downloading `input/source.url`, passing it through a new URL-extractor behaviour, and uploading `extract/text.txt`.
- Added `Gallformers.IngestionPipeline.Stages.Extract.URLExtractor` plus default `ReqURLExtractor`, which validates http/https URLs, fetches with `Req`, and reduces HTML responses to plain text for downstream stages.
- Expanded `test/support/fixtures/ingestion_pipeline_fixtures.ex` with duplicate-candidate evidence support, review-ready ingestion helpers, ordered species-entry helpers, and realistic extraction payload defaults for later phases.
- Verification: `mix compile --warnings-as-errors`, focused ingestion/extract tests, relevant broader ingestion pipeline tests, and full `mix precommit` all passed.

No planned deviations from the Phase 1 matter requirements.

Phase 2 completed on 2026-05-01.

- Replaced the `/admin/ingestion-review` PoC route with `GallformersWeb.Admin.IngestionReviewLive.Index`, backed exclusively by `Gallformers.Ingestions.list_source_ingestion_queue_rows/1`.
- Added a persisted queue page using existing reusable components only: `card`, `table`, `badge`, `toggle`, `radio_group`, `input`, and the existing PDF `file_dropzone`.
- Queue state now includes persisted rows, `include_complete`, uploader scope (`:me`/`:all` with DB-user fallback to `:all`), and separate PDF/URL/text submission form state.
- Queue rows render the required columns and labels: title, species progress, status via `queue_status_label/1`, upload date, uploader name, and a distinct duplicate-review badge.
- Added new-source submission UX for PDF, URL, and text on the queue page. Success redirects to `/admin/ingestion-review/:id`; validation stays on the queue page; enqueue failures surface a user-visible error.
- Added a minimal `GallformersWeb.Admin.IngestionReviewLive.Show` shell plus the `/admin/ingestion-review/:id` route so the new canonical detail path resolves immediately between phases. Full duplicate/source/gall review behavior remains Phase 3 work.
- Replaced the old PoC LiveView test file with `test/gallformers_web/live/admin/ingestion_review_live/index_test.exs`, covering persisted rendering, default complete-item hiding, uploader filter behavior, duplicate badge rendering, PDF/URL/text submission success, failure handling, and detail-path navigation links.
- Verification: `mix compile --warnings-as-errors`, the Phase 2 LiveView test file, and full `mix precommit` all passed.

Implementation note: the minimal `Show` LiveView is an intentional bridge so queue navigation and redirects land on the canonical persisted detail path before Phase 3 replaces that shell with the full review workflow.

Phase 3 complete on 2026-05-01.

Implemented the real persisted detail page at `/admin/ingestion-review/:id` with duplicate review as the first blocking gate. `Gallformers.Ingestions.source_ingestion_review_view!/1` now shapes the detail-page state from `get_source_ingestion_with_details!/1`, including duplicate candidates, mapped evidence rows, ordered species entries, unlock booleans, and header counts. `GallformersWeb.Admin.IngestionReviewLive.Show` renders the duplicate-review workflow, uses only `DuplicateResolution.confirm_duplicate/2`, `reject_duplicate/2`, and `promote_to_unique/2` for actions, reloads from persisted state after each action, and keeps source/gall controls locked while duplicate review is unresolved.

To keep the LiveView tests exercising the real duplicate-resolution path without advancing the worker inline, `Gallformers.IngestionPipeline.DuplicateResolution` now resolves its worker module from app config with the real worker as the default. The Phase 3 coverage landed in `test/gallformers_web/live/admin/ingestion_review_live/show_duplicate_review_test.exs`, and I also made duplicate-candidate ordering explicit so pending candidates stay first in the persisted review view.

Verification passed with `mix compile --warnings-as-errors`, focused Phase 3 LiveView tests, adjacent ingestion/duplicate-resolution tests, and full `mix precommit`.

Phase 4 complete on 2026-05-01.

Implemented persisted source resolution and the unlocked gall list on `GallformersWeb.Admin.IngestionReviewLive.Show`. The detail page now renders submission metadata strictly from `source_ingestions` fields, uses the shared `typeahead` component plus `Sources.search_sources/1` / `Sources.get_source!/1` for source lookup, keeps `select_source` transient, persists only through `Ingestions.associate_source/2`, and clears persisted links only through `Ingestions.clear_source_association/1`. The source picker links to `/admin/sources/new` in a new tab for missing references.

`Gallformers.Ingestions.source_ingestion_review_view!/1` now includes the persisted metadata and associated-source summary needed by the page, plus gall row shaping for mapped species names and host counts. The gall review card now renders directly from ordered `source_ingestion_species` rows, uses persisted counts in its progress header, treats invalid or missing host payloads as zero hosts, and exposes row-level review actions only after a source association exists.

Coverage landed in `test/gallformers_web/live/admin/ingestion_review_live/show_source_resolution_test.exs` for metadata rendering, source typeahead search, select-vs-associate behavior, clear association, gall ordering/host counts, and lock/unlock behavior. Verification passed with `mix compile --warnings-as-errors`, focused detail/ingestion tests, and full `mix precommit`.

Phase 5 complete on 2026-05-01.

Implemented the persisted gall review workspace on `GallformersWeb.Admin.IngestionReviewLive.Show` using the existing modal and form components. One workspace session now loads exactly one persisted `source_ingestion_species` row, supports gall-species search via `Species.search_species_by_name/3`, alias collision warnings via `Species.find_species_with_alias/1`, host review search via the same species APIs with plant taxoncode, trait selection using the existing controlled-vocabulary component patterns, and direct editing of `description_prose`.

Added the single persistence API required by this phase: `Ingestions.update_source_ingestion_species_review/3`. The context now also shapes persisted workspace state for modal loading and normalizes the fixed `review_payload` structure, including `species_review`, `host_reviews`, `trait_reviews`, and `description_review`. Status handling now follows the matter rules: normal saves produce `mapped` or `skipped` from the persisted species decision, `complete` is only allowed when the source is associated, the gall species is mapped, host reviews are resolved, and the description has been reviewed.

Coverage landed in `test/gallformers_web/live/admin/ingestion_review_live/show_workspace_test.exs`, with adjacent context coverage added in `test/gallformers/ingestions_test.exs`. Verification passed with `mix compile --warnings-as-errors`, the focused and adjacent ingestion-review/detail tests, and full `mix precommit`.

## 2026-05-02 follow-up: Auth0-backed ingestion attribution

Removed the user-facing database-profile gate from the persisted ingestion review UI. The ingestion queue and detail LiveViews now resolve reviewer/submission attribution by syncing the current Auth0 admin user into `users` on demand when no local profile row exists yet, matching the attribution pattern used elsewhere in admin flows. Added regression coverage for Auth0-only sessions submitting new ingestions and resolving duplicate-review actions.

## Phase 6 shipped

Completed the persisted ingestion review workflow end-to-end.

- Added `Gallformers.Ingestions.maybe_complete_source_ingestion_review/1` and now call it after every successful gall-workspace save so `needs_review` ingestions transition to `complete` as soon as every `source_ingestion_species` row is resolved.
- Locked the active queue semantics to hide both `complete` and `duplicate_confirmed` rows by default while still leaving `failed` rows visible.
- Removed the last PoC ingestion review LiveView that depended on local output directories, pipeline hashes, and shell-out execution.
- Added Phase 6 coverage for completion transitions, queue finalization, and a happy path from persisted submission through completed review.

Verification passed with:
- `mix compile --warnings-as-errors`
- focused ingestion review tests
- `mix precommit`

Deferred follow-ups retained from this matter:
- `docx` submission
- canonical root promotion or swapping
- dedicated ingestion reviewer role
- inline source creation workflow
- writing workspace review decisions into real domain tables in a later matter

## 2026-05-02 follow-up: orchestration lock timeout handling

Fixed a local pipeline stall where long-running ingestion stages could outlive the `Repo.checkout` window used for the advisory orchestration lock. `Gallformers.Ingestions.with_source_ingestion_orchestration_lock/2` now uses an explicit configurable checkout timeout and no longer lets a `DBConnection.ConnectionError` during advisory unlock mask the actual stage result. Added worker coverage for configurable lock timeouts with slow paused stages.

2026-05-02 follow-up: added failed-ingestion cleanup for the persisted review workflow. `Gallformers.Ingestions.delete_failed_source_ingestion/1` now deletes private artifacts and then removes the DB row, but only for terminal `failed` ingestions. The review queue now shows a confirmed clear action for failed rows, and the failed detail page also exposes a clear action. Added context and LiveView regression coverage for queue/detail cleanup flows plus non-failed rejection and artifact-delete failure handling. Verification passed with `mix compile --warnings-as-errors`, focused ingestion/index/show tests, and full `mix precommit`.

2026-05-02 follow-up: fixed the LLM chunk-stage timeout path and processing-step visibility. `llm_clean` and `data_extract` now use configurable concurrency/timeouts, lower default concurrency, longer default time budgets, and `Task.async_stream(..., on_timeout: :kill_task)` so stage timeouts return normal `:timeout` errors instead of crashing the worker and stranding the ingestion. Queue/detail status display now derives the active processing step from the next runnable workflow stage, so a row checkpointed at `metadata` renders as `data_extract` while that stage is active/retrying. Added abandoned-ingestion cleanup: detail-page clear action now works for terminal `failed` rows and for `processing` rows whose ingestion worker was discarded, allowing recovery from previously stranded local dev ingestions. Verification passed with `mix compile --warnings-as-errors`, focused ingestion/LLM-stage/detail tests, and full `mix precommit`.
