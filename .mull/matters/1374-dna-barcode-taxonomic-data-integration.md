---
status: raw
created: 2026-02-13
updated: 2026-09-10
epic: taxonomy
---

# DNA barcode / taxonomic data integration

DNA data accessibility has exploded since site launch. Critical for taxonomy resolution, especially as geographic and associate expansion happens. Can't defer.


## Clarified use case and linked issue — 2026-09-10

Jeff's intended outcome is to store barcode evidence that can connect an undescribed gall to a barcoded organism. This is not simply an external-link feature. More domain input from Adam (Megachile) may be needed before specifying the model.

Source: https://github.com/jeffdc/gallformers/issues/561 — "Allow DNA barcodes to be added to galls", opened by Megachile.

The issue specifies:
- Prefer linking barcodes to galls through observations, rather than directly.
- Support multiple instances of multiple barcode regions, including COI, cytb, and ITS.
- Design external-database integration so it is not brittle.
- Hashing barcodes for join operations is a possibility to investigate, not a decided approach.

Relationship to 2cb2: preserve the separation between gall structure and organism/taxon identity. Observation-linked barcode evidence could support a relationship to a provisional unnamed organism; it must not automatically establish a formally described species or prove that a sequenced associate is the inducer.

Open questions for Adam: what observation/voucher and sequenced-organism records must be represented; raw sequence versus accessions (or both); repeated samples/regions; how organism determinations and gall association evidence are established and revised; external repositories and matching semantics. No schema, priority, or formal dependency is approved by this note. Broader direction is captured in 4dcd: paper ingestion plus a full existing-source backscan is Jeff's leading product outcome, with taxonomy and finer-grained provenance requiring joint design.

