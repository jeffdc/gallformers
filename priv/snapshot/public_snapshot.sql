-- Run by .github/workflows/db-snapshot.yml on the scratch copy, before the
-- private tables (priv/snapshot/tables.txt) are dropped: the public tables
-- the snapshot derives from private ones.
--
-- gall_notes: each Gall's Gallformers notes ("Notes on ID and Taxonomy"),
-- public on gall pages and in today's snapshot (as species_source rows of
-- the Gallformers Source). They are stored as note documents
-- (source_documents of kind 'note', their text in document_items), which
-- also hold Sources' stored text and so stay private. Every version, by
-- version_date (undated legacy notes have none); the text is the note's
-- items in order.
--
-- One statement, so the test suite can run this file as it is
-- (test/gallformers/public_snapshot_test.exs).
CREATE TABLE gall_notes AS
SELECT d.gall_id,
       d.source_id,
       d.version_date,
       string_agg(i.text, E'\n\n' ORDER BY i.position) AS text
FROM source_documents d
JOIN document_items i ON i.source_document_id = d.id
WHERE d.kind = 'note'
GROUP BY d.id, d.gall_id, d.source_id, d.version_date
ORDER BY d.gall_id, d.version_date NULLS FIRST, d.id;
