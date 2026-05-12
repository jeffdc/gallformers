"""Tests for the substring verification gate."""

from __future__ import annotations

from ingest.schemas import (
    Evidence,
    EvidenceCell,
    NormalizedBlock,
    ScientificNameCell,
    SupportStatus,
    TraitCell,
    WarningType,
)
from ingest.verify import _index_blocks, gate_cell

# A flat normalized text composed of three blocks separated by "\n\n".
#
# Block 1 at offsets [0, 50): "Andricus quercuscalifornicus forms an oak gall."
# Sep "\n\n"               [50, 52)
# Block 2 at offsets [52, 105): "The gall is globular and bright red at maturity."
# Sep "\n\n"               [105, 107)
# Block 3 at offsets [107, ...]: "Galls are found on Quercus agrifolia."
BLOCK_1_TEXT = "Andricus quercuscalifornicus forms an oak gall."
BLOCK_2_TEXT = "The gall is globular and bright red at maturity."
BLOCK_3_TEXT = "Galls are found on Quercus agrifolia."


def _blocks() -> list[NormalizedBlock]:
    b1_start = 0
    b1_end = b1_start + len(BLOCK_1_TEXT)
    b2_start = b1_end + 2  # after "\n\n"
    b2_end = b2_start + len(BLOCK_2_TEXT)
    b3_start = b2_end + 2
    b3_end = b3_start + len(BLOCK_3_TEXT)
    return [
        NormalizedBlock(
            span_id="S_0001",
            block_id="p1-b0",
            page=1,
            char_start=b1_start,
            char_end=b1_end,
            text=BLOCK_1_TEXT,
            raw_block_ids=["p1-b0"],
        ),
        NormalizedBlock(
            span_id="S_0002",
            block_id="p1-b1",
            page=1,
            char_start=b2_start,
            char_end=b2_end,
            text=BLOCK_2_TEXT,
            raw_block_ids=["p1-b1"],
        ),
        NormalizedBlock(
            span_id="S_0003",
            block_id="p1-b2",
            page=2,
            char_start=b3_start,
            char_end=b3_end,
            text=BLOCK_3_TEXT,
            raw_block_ids=["p1-b2"],
        ),
    ]


def _evidence(block_id: str, quote: str, page: int = 1) -> Evidence:
    return Evidence(
        block_id=block_id,
        page=page,
        char_start=0,  # placeholder; gate enriches
        char_end=1,
        quote=quote,
    )


class TestGateEvidenceCell:
    def test_exact_match_enriches_with_absolute_offsets(self):
        blocks = _blocks()
        cell = EvidenceCell(
            value="globular",
            evidence=[_evidence("S_0002", "globular")],
            support_status=SupportStatus.SUPPORTED,
            confidence=0.9,
        )
        gated, warnings = gate_cell(
            cell,
            _index_blocks(blocks),
            field_path="gall_traits.shape",
            record_id="R_001",
        )
        assert warnings == []
        assert gated.value == "globular"
        assert gated.support_status == SupportStatus.SUPPORTED
        assert len(gated.evidence) == 1
        ev = gated.evidence[0]
        b2_start = blocks[1].char_start
        assert ev.char_start == b2_start + BLOCK_2_TEXT.index("globular")
        assert ev.char_end == ev.char_start + len("globular")
        assert ev.page == 1

    def test_evidence_in_second_block_uses_that_blocks_offset(self):
        blocks = _blocks()
        cell = EvidenceCell(
            value="Quercus agrifolia",
            evidence=[_evidence("S_0003", "Quercus agrifolia", page=2)],
            support_status=SupportStatus.SUPPORTED,
            confidence=0.95,
        )
        gated, warnings = gate_cell(
            cell,
            _index_blocks(blocks),
            field_path="hosts[0].scientific_name",
            record_id="R_001",
        )
        assert warnings == []
        ev = gated.evidence[0]
        assert ev.page == 2
        # Block 3 starts at 0 + 50 + 2 + 50 + 2 = NOT relevant
        # Compute properly: BLOCK_1 (47) + "\n\n" (2) + BLOCK_2 (48) + "\n\n" (2) = 99
        # then "Quercus agrifolia" is at index 19 of BLOCK_3 ("Galls are found on ").
        b3_start = len(BLOCK_1_TEXT) + 2 + len(BLOCK_2_TEXT) + 2
        local = BLOCK_3_TEXT.index("Quercus agrifolia")
        assert ev.char_start == b3_start + local
        assert ev.char_end == ev.char_start + len("Quercus agrifolia")


class TestGateFailures:
    def test_substring_mismatch_nulls_value_and_emits_warning(self):
        blocks = _blocks()
        # Quote that doesn't appear anywhere in any block.
        cell = EvidenceCell(
            value="Hocus pocus",
            evidence=[_evidence("S_0001", "Hocus pocus abracadabra completely off")],
            support_status=SupportStatus.SUPPORTED,
            confidence=0.5,
        )
        gated, warnings = gate_cell(
            cell,
            _index_blocks(blocks),
            field_path="gall_maker.scientific_name",
            record_id="R_001",
        )
        assert gated.value is None
        assert gated.support_status == SupportStatus.EVIDENCE_SUBSTRING_MISMATCH
        assert len(warnings) == 1
        assert warnings[0].type == WarningType.EVIDENCE_SUBSTRING_MISMATCH
        assert warnings[0].record_id == "R_001"
        assert warnings[0].field_path == "gall_maker.scientific_name"
        assert warnings[0].detail["block_id"] == "S_0001"
        assert warnings[0].detail["claimed_quote"].startswith("Hocus pocus")
        assert warnings[0].detail["score"] < 90

    def test_unknown_block_id_fails(self):
        blocks = _blocks()
        cell = EvidenceCell(
            value="something",
            evidence=[_evidence("nonexistent-block", "anything")],
            support_status=SupportStatus.SUPPORTED,
            confidence=0.9,
        )
        gated, warnings = gate_cell(
            cell,
            _index_blocks(blocks),
            field_path="x.y",
            record_id="R_001",
        )
        assert gated.value is None
        assert gated.support_status == SupportStatus.EVIDENCE_SUBSTRING_MISMATCH
        assert len(warnings) == 1
        assert warnings[0].detail["block_text"] is None

    def test_any_failed_evidence_nulls_the_whole_cell(self):
        blocks = _blocks()
        cell = EvidenceCell(
            value="something",
            evidence=[
                _evidence("S_0001", "Andricus"),  # passes
                _evidence("S_0002", "TOTALLY ABSENT TEXT"),  # fails
            ],
            support_status=SupportStatus.SUPPORTED,
            confidence=0.9,
        )
        gated, warnings = gate_cell(
            cell,
            _index_blocks(blocks),
            field_path="x",
            record_id="R_001",
        )
        # Whole cell nulled even though the first evidence passed.
        assert gated.value is None
        assert gated.support_status == SupportStatus.EVIDENCE_SUBSTRING_MISMATCH
        assert len(warnings) == 1  # only the failed one


class TestGateScientificNameCell:
    def test_scientific_name_cell_value_nulled_but_name_as_written_preserved(self):
        blocks = _blocks()
        cell = ScientificNameCell(
            value="Andricus quercuscalifornicus",
            name_as_written="Andricus quercus-cαlifornicus",  # OCR damage preserved
            evidence=[_evidence("S_0001", "BAD_QUOTE_NOT_PRESENT_ANYWHERE")],
            support_status=SupportStatus.SUPPORTED,
            confidence=0.9,
        )
        gated, warnings = gate_cell(
            cell,
            _index_blocks(blocks),
            field_path="gall_maker.scientific_name",
            record_id="R_001",
        )
        assert gated.value is None
        # name_as_written is the source-text excerpt; it's not a claim, so
        # it survives a substring-gate failure.
        assert gated.name_as_written == "Andricus quercus-cαlifornicus"
        assert len(warnings) == 1


class TestGateTraitCell:
    def test_failure_nulls_suggested_but_keeps_original(self):
        blocks = _blocks()
        cell = TraitCell(
            original="bright red",
            suggested=["red"],
            evidence=[_evidence("S_0002", "BAD_QUOTE_NOT_PRESENT")],
            support_status=SupportStatus.SUPPORTED,
            confidence=0.9,
        )
        gated, warnings = gate_cell(
            cell,
            _index_blocks(blocks),
            field_path="gall_traits.color",
            record_id="R_001",
        )
        # Suggested cleared (it's the claim); original preserved (source phrase).
        assert gated.suggested == []
        assert gated.original == "bright red"
        assert gated.support_status == SupportStatus.EVIDENCE_SUBSTRING_MISMATCH
        assert len(warnings) == 1

    def test_pass_preserves_suggested_and_enriches_offsets(self):
        blocks = _blocks()
        cell = TraitCell(
            original="bright red",
            suggested=["red"],
            evidence=[_evidence("S_0002", "bright red")],
            support_status=SupportStatus.SUPPORTED,
            confidence=0.9,
        )
        gated, warnings = gate_cell(
            cell,
            _index_blocks(blocks),
            field_path="gall_traits.color",
            record_id="R_001",
        )
        assert warnings == []
        assert gated.suggested == ["red"]
        assert gated.original == "bright red"
        assert gated.support_status == SupportStatus.SUPPORTED
        ev = gated.evidence[0]
        b2_start = blocks[1].char_start
        assert ev.char_start == b2_start + BLOCK_2_TEXT.index("bright red")
