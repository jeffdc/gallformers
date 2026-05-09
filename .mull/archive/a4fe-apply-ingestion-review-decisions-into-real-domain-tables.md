---
status: done
created: 2026-05-01
updated: 2026-05-08
epic: ingestion
---

# Apply ingestion review decisions into real domain tables

## Scope

Follow up after `7c67` to turn persisted ingestion review decisions into real database writes in the core domain model.

This matter is intentionally not planned yet. It exists so the work is tracked separately from `7c67`.

## Intended Work

Potential scope includes:
- writing approved gall review decisions into real domain tables instead of only `source_ingestion_species.review_payload`
- creating or updating `species_source` records from reviewed ingestion prose
- applying approved gall trait values into the real gall trait tables
- applying approved host mappings into real host association tables
- deciding whether alias creation, taxonomy updates, or new-species creation belong in this workflow or in separate follow-ups

## Relationship To Existing Work

- blocked on `7c67` reaching a stable persisted review workflow
- should reuse the reviewer decisions captured by `source_ingestion_species`
- should not be folded back into `7c67` unless priorities change explicitly
