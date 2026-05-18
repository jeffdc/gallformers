"""Schema-shape contract tests. Pinning structural changes that matter to
the bundle contract — fields that downstream consumers (the Elixir review
workspace, exporters) rely on existing or being gone."""

from __future__ import annotations

import pytest
from pydantic import ValidationError

from ingest.schemas import EvidenceCell, GallRecord, ProseParagraph, SupportStatus, TraitCell


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


class TestAbstentionShapes:
    """Pin the abstention payload shapes the extract-facts prompt documents.

    The prompt MUST give the LLM templates that round-trip through these
    schemas — otherwise abstaining traits trip Instructor's strict-validator
    and the candidate burns retries on schema fixups. (See the Nicholls run
    on 2026-05-18 where every TraitCell abstention failed because the prompt
    showed only the EvidenceCell template.)"""

    def test_evidence_cell_abstention_template_validates(self):
        """The EvidenceCell abstention shape — used for `detachable`,
        `location`, and the gall_maker/host cells."""
        EvidenceCell.model_validate(
            {
                "value": None,
                "evidence": [],
                "support_status": "abstained",
                "confidence": 0.0,
            }
        )

    def test_trait_cell_abstention_template_validates(self):
        """The TraitCell abstention shape — used for color, shape, texture,
        walls, cells, alignment, plant_part, form, season."""
        TraitCell.model_validate(
            {
                "original": None,
                "suggested": [],
                "evidence": [],
                "support_status": "abstained",
                "confidence": 0.0,
            }
        )

    def test_evidence_cell_template_fails_on_trait_cell(self):
        """The EvidenceCell template MUST NOT validate against TraitCell —
        if this stops failing, the schema has drifted and the prompt's
        per-shape callouts may be silently wrong."""
        with pytest.raises(ValidationError):
            TraitCell.model_validate(
                {
                    "value": None,
                    "evidence": [],
                    "support_status": "abstained",
                    "confidence": 0.0,
                }
            )

    def test_trait_cell_template_fails_on_evidence_cell(self):
        """The TraitCell template MUST NOT validate against EvidenceCell."""
        with pytest.raises(ValidationError):
            EvidenceCell.model_validate(
                {
                    "original": None,
                    "suggested": [],
                    "evidence": [],
                    "support_status": "abstained",
                    "confidence": 0.0,
                }
            )

    def test_detachable_abstention_uses_unknown_enum_value(self):
        """`detachable` is the lone EvidenceCell in gall_traits. Its
        abstention template uses `value: "unknown"` from the Detachable
        enum — not `value: null`. Documented in the prompt."""
        cell = EvidenceCell.model_validate(
            {
                "value": "unknown",
                "evidence": [],
                "support_status": "abstained",
                "confidence": 0.0,
            }
        )
        assert cell.value == "unknown"
        assert cell.support_status == SupportStatus.ABSTAINED
