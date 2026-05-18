"""Schema-shape contract tests. Pinning structural changes that matter to
the bundle contract — fields that downstream consumers (the Elixir review
workspace, exporters) rely on existing or being gone."""

from __future__ import annotations

from ingest.schemas import GallRecord, ProseParagraph


class TestProseParagraphFields:
    def test_carries_relevance_and_citation_signals(self):
        """ProseParagraph carries every signal the curator UI needs: char
        offsets for in-context highlights, is_mention / is_cited / name
        signals for chunk filtering, and a bucketed relevance hint."""
        fields = ProseParagraph.model_fields
        assert "char_start" in fields
        assert "char_end" in fields
        assert "is_mention" in fields
        assert "is_cited" in fields
        assert "cited_by_fields" in fields
        assert "name_occurrences" in fields
        assert "relevance" in fields


class TestGallRecordDescriptionRemoved:
    def test_no_description_field(self):
        """The synthesized description EvidenceCell is gone — descriptions are
        curator-built from selected evidence_prose chunks, not LLM-synthesized."""
        assert "description" not in GallRecord.model_fields
