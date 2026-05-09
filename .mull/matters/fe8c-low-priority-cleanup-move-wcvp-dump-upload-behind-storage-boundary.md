---
status: refined
tags: [low-priority]
effort: small
created: 2026-04-28
updated: 2026-05-08
epic: source-ingestion
---

# Low-priority cleanup: move WCVP dump upload behind storage boundary

## Goal

Evaluate whether the WCVP build/upload task should move its remaining S3 multipart upload construction behind a storage-owned API.

This was split out of `cab4` because it is operational tooling, not application runtime behavior, and should not block or enlarge the main storage-boundary refactor.

## Context

The WCVP build task currently performs its upload path in `Mix.Tasks.Gallformers.Wcvp.BuildDb`.

Relevant behavior today:
- the `--upload` path is optional and operator-invoked
- the task is not part of production runtime request handling
- it already routes final request execution through `Gallformers.Storage.S3`
- but it still constructs multipart upload operations in the Mix task layer via `ExAws.S3.Upload` / `ExAws.S3`

Current code reference:
- `lib/mix/tasks/gallformers/wcvp/build_db.ex`

## Why this is low priority

- The task is rarely run.
- The upload path is even rarer because it only happens when `--upload` is requested.
- The current implementation is pragmatic and isolated to tooling.
- The code already opts out of normal boundary enforcement with `use Boundary, check: [in: false, out: false]`, which is appropriate for this kind of operational task.

This means the architectural benefit is mainly consistency, not meaningful runtime risk reduction.

## Objective

If we choose to do this later, make the storage boundary explicit for the WCVP dump upload path without forcing a broader redesign of the WCVP build process.

## Work

1. Audit the current WCVP upload flow and isolate what is truly storage-related versus orchestration-related.
2. Introduce a storage-owned home only if it materially improves clarity.
3. Decide the shape of that home:
   - a narrow helper inside `Gallformers.Storage`
   - a dedicated storage slice for backups / WCVP artifacts
   - or another clearly storage-owned module if that proves cleaner
4. Move bucket/key naming for the uploaded dump out of the Mix task if we proceed.
5. Move multipart upload construction out of the Mix task and behind the storage-owned API.
6. Keep the Mix task responsible only for orchestration:
   - building the dump
   - deciding whether upload should happen
   - reporting success/failure to the operator
7. Preserve streaming upload behavior so large dumps are not loaded fully into memory.
8. Add or adjust tests around the extracted upload boundary only if the extraction is actually landed.

## Design intent

The Mix task should decide that a WCVP dump needs to be uploaded, but it does not necessarily need to know how multipart S3 upload operations are assembled.

## Expected result

If implemented:
- task-level multipart upload construction moves behind a storage-owned API
- operational upload behavior remains unchanged
- the codebase gains consistency without dragging this concern into runtime storage work

If not implemented:
- the current Mix task remains an intentional tooling exception
- no runtime storage boundary is compromised

## Non-goals

- redesigning the WCVP import/build process itself
- changing dump format or retention policy unless a small improvement is obvious
- treating this as required follow-up for the main storage refactor
