---
status: raw
created: 2026-10-03
updated: 2026-10-15
epic: taxonomy
relates: [1121, 8567, 294c, ca20]
---

# Import interface: pipeline to Gallformers

# Import interface: pipeline to Gallformers

The Gallformers side of import: taking a package (contract `294c`, `priv/import/`) into the database. Any tool, screen, person or LLM that produces a valid package can deliver data. What Gallformers does on import is listed in `docs/import/producer-guide-background.md`, "What Gallformers does on import". Depends on the taxonomy work (`8567`, facade `36ca`).

## Decisions

- **Delivery:** a package (document, taxonomy batch, gall batch, review) is written to the private S3 bucket; an Oban job imports it as unpublished. A curator upload is a UI over the same path.
- **One Source per package;** the Source is the replacement key. `replace` re-imports replace that Source's attributions (behind an overwrite warning), not Facts: a Fact another Source supports survives; one left unsupported is hidden, and the audit log keeps it. `add` supplements. Gallformers' own statements are always `add`.
- **Stances and recency** (`8567`): every Fact is confirm or deny; newest authorship date wins.
- **Humans approve every database change.** Extraction or review status never writes to the database by itself. Taxonomy batch first, then gall batch.
- **Admin queue:** ambiguous name matches (with a proposed match and reason), undescribed-Gall candidates, unresolved names, and phase 6 disputes (statement, quote, reviewer's reason, producer's reason; accept or reject). Nothing ambiguous is applied automatically. Old Sources will produce many of these (pre-1925 Sources are about a quarter of all Sources).
- **Provenance both ways:** why Gall X has Host Y, and every accepted assertion attributable to Source Z.
- **Editing** happens only during import, before publishing; afterwards a curator adds a Gallformers statement.
- **Observations** appear only as cited evidence on a Fact.
- **Documents and text** are stored privately; text is shown publicly only where the license allows. Verbatim description excerpts keep today's practice (short quoted excerpts with citation).
- **Storage release gate** (carried from the old ingestion plan): before production, verify the private bucket blocks public access, application credentials can read/write/list/delete privately, incomplete multipart uploads expire after seven days, and only approved public outputs reach the public bucket.

## Remaining work

- Build the importer (the dry-run behaviour approximated in `services/import-producer/scripts/dryrun.py`), the admin queue and the intake view of disputes.
- Test the "no silent merges" gate (taxonomy batch applied before name resolution) once the importer exists.
- Historical plant names (`d585`).
- Retire the old source-ingestion system (new matter).

