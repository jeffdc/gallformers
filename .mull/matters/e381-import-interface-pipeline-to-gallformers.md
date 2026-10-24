---
status: raw
created: 2026-10-03
updated: 2026-10-23
epic: taxonomy
relates: [8567, 294c]
---

# Import interface: pipeline to Gallformers

# Import interface: pipeline to Gallformers

The Gallformers side of import: taking a package (contract `294c`, `priv/import/`) into the database. Any tool, screen, person or LLM that produces a valid package can deliver data. What Gallformers does on import is listed in `docs/import/producer-guide-background.md`, "What Gallformers does on import". Depends on the new back-end (`8567` *Build approach*).

## Decisions

- **Delivery:** a package (document, taxonomy batch, gall batch, review) is written to the private S3 bucket; an Oban job imports it as unpublished. A curator upload is a UI over the same path.
- **One Source per package;** the Source is the replacement key. `replace` re-imports replace that Source's attributions (behind an overwrite warning), not Facts: a Fact another Source supports survives; one left unsupported is hidden, and the audit log keeps it. `add` supplements. Gallformers' own statements are always `add`. **A re-import changes only what changed** (2026-10-24): an unchanged attribution is not deleted and reinserted, so the audit log and standings don't churn. **Import is idempotent:** an Oban retry, or replaying staging decisions at cutover (`b5bd` M0), never applies the same change twice.
- **Stances and recency** (`8567`): every Fact is confirm or deny; newest authorship date wins.
- **Humans approve every database change.** Extraction or review status never writes to the database by itself. Taxonomy batch first, then gall batch. **In phase 1** (Jeff, 2026-10-24; `9449` §3) an approved taxonomy batch records every act as a Fact, changes the tree only to add taxa the Source presents as new, and flags every act that disagrees with the tree for a curator; gall names never resolve through a disagreement silently. Tables and apply steps: `9449` §5.
- **Unresolved Host names are resolved before the gall batch** (Adam and Jeff, 2026-10-17; `d585`), as part of the taxonomy step. Gallformers holds plant synonymy, but POWO is unreliable for old gall Sources. The importer collects the Host names it can't resolve; an admin resolves each (adds a synonym or the plant); only then does the gall batch import.
- **Admin queue:** ambiguous name matches (with a proposed match and reason), undescribed-Gall candidates, unresolved names, and phase 6 disputes (statement, quote, reviewer's reason, producer's reason; accept or reject). Nothing ambiguous is applied automatically. Old Sources will produce many of these (pre-1925 Sources are about a quarter of all Sources).
- **Provenance both ways:** why Gall X has Host Y, and every accepted assertion attributable to Source Z.
- **Editing** happens only during import, before publishing; afterwards a curator adds a Gallformers statement.
- **Observations** appear only as cited evidence on a Fact.
- **Recorded occurrences** (Adam and Jeff, 2026-10-17): a new gall-batch Fact kind (`occurrence`: place, optional when and stage as written). It feeds the range map and the phenology tool, separately from range adjustments.
- **Season changes meaning** (Adam and Jeff, 2026-10-17): it is when the Gall forms and grows, not when it can be observed. The ID tool's season filter, described on the site as "when galls can be observed" (193 galls tagged Winter, 33 only Winter), takes the new meaning. Today's tags don't carry over, since the plan is a fresh database built from imports.
- **Documents and text** are stored privately; text is shown publicly only where the license allows. Verbatim description excerpts keep today's practice (short quoted excerpts with citation).
- **Storage release gate** (carried from the old ingestion plan): before production, verify the private bucket blocks public access, application credentials can read/write/list/delete privately, incomplete multipart uploads expire after seven days, and only approved public outputs reach the public bucket. The public database snapshot (`db-snapshot.yml`) must exclude the new private tables (`b5bd` M3).

## Remaining work

- Build the importer (the dry-run behaviour approximated in `services/import-producer/scripts/dryrun.py`), the admin queue and the intake view of disputes.
- The Host-name resolution step before the gall batch, with its admin screen (`d585`).
- Store recorded occurrences for the range map and the phenology tool.
- Update the ID tool's season filter wording to the new meaning.
- Test the "no silent merges" gate (taxonomy batch applied before name resolution) once the importer exists.

