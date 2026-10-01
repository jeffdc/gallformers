---
status: raw
created: 2026-09-11
updated: 2026-09-13
epic: source-ingestion
---

# Backscan all existing sources with accepted-claim provenance

## Goal

Process and review ALL existing Gallformers sources through the real LLM-assisted ingestion workflow, reconciling accepted assertions with existing records and preserving queryable supporting evidence. This is Jeff's stated product goal, not a new priority invented by this matter.

## Status

Raw execution-tracking matter created during the proposed sequencing discussion. No implementation design, schedule, or formal dependency change is approved. The older roadmap 9314 describes pipeline evolution, not a dedicated full-existing-source backscan. The proposed order is recorded in 4dcd.

## High-level work

- Prepare an inventory of every existing source and its available document material; distinguish born-digital, scanned/mixed, and unavailable/unsupported material. Preparation can run alongside the proposed taxonomy foundation and OCR work.
- Reconcile each processing run to the existing source rather than blindly creating new source/gall records.
- Review extracted facts against existing curated information. Only accepted claims enter provenance queries, with their specific source evidence retained.
- Support restarting/reprocessing without duplicating accepted assertions or their supporting evidence, and preserve existing curator work.
- Track processing/review outcomes across the full inventory. A sample, completed machine extraction, or an unprocessed-source list does not establish completion of the full backscan. Missing or unsupported documents remain explicit outstanding work requiring resolution or an owner-approved exception.

## Proposed sequencing, subject to 4dcd approval

- Corpus inventory/preparation is independent of the taxonomy migration.
- Production approval/writeback depends on the reduced gall/taxon/provenance foundation (proposed revised 2cb2 scope) and the production ingestion/review workflow (7fda with 7c67).
- Born-digital sources can enter processing/review once that workflow is ready; they need not wait for OCR.
- Scanned-source processing and completion across the entire corpus also require 4fef OCR support. OCR is not a blocker for preparing the inventory or processing supported documents.
- Optional pipeline polish 7a83 is not a hard prerequisite. 9314 and ce28 remain roadmap/design context; completed c744 remains the versioned producer-bundle baseline, not work to redo.

## Non-goals

Do not implement a store of every unaccepted claim, silently replace curator conclusions, invent per-fact citations from legacy source links, or make unrelated taxonomy/integration features prerequisites. This matter does not authorize starting production batch processing.


## Ownership after ce28 consolidation

ce28 is being closed as superseded design context, not as completion of ingestion or the backscan. Its remaining corpus-wide product outcome is owned here: process and review ALL existing Sources, including reconciling to curated records and retaining specific evidence for accepted assertions, under the scope and outstanding-material rules above.

The current producer baseline (c744), 9314's representative 30+ document gold evaluation, and a successful production sample are distinct milestones; none establishes full-source completion. 4fef owns scanned-document capability, 9314 owns producer quality, fa48/7c67 own review design/implementation, and 7fda owns production integration and storage/publication release gates. Historical references to ce28 are not an active dependency. No batch run, taxonomy decision or scope exception is authorized by this consolidation.

