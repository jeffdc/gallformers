"""Tests for the per-candidate evidence pack builder."""

from __future__ import annotations

import pytest

from ingest.evidence_pack import build_evidence_pack
from ingest.schemas import Candidate, NormalizedBlock


def _block(span_id: str, text: str, section_id: str = "sec-1", page: int = 1) -> NormalizedBlock:
    return NormalizedBlock(
        span_id=span_id,
        block_id=span_id,
        page=page,
        section_id=section_id,
        char_start=0,  # offsets aren't relevant to evidence pack logic
        char_end=len(text),
        text=text,
        raw_block_ids=[span_id],
    )


def _candidate(mention_span_ids: list[str], cid: str = "C_001") -> Candidate:
    return Candidate(
        candidate_id=cid,
        gall_maker_mention="Andricus quercuscalifornicus",
        mention_span_ids=mention_span_ids,
        sample_agreement=3,
    )


class TestSingleMention:
    def test_window_zero_yields_only_the_mention_block(self):
        blocks = [_block(f"S_{i:04d}", f"text {i}") for i in range(1, 6)]
        cand = _candidate(["S_0003"])
        text, meta = build_evidence_pack(cand, blocks, context_window=0)
        assert meta["allowed_span_ids"] == ["S_0003"]
        assert text == "[S_0003] text 3"

    def test_window_two_yields_five_blocks_around_mention(self):
        blocks = [_block(f"S_{i:04d}", f"text {i}") for i in range(1, 6)]
        cand = _candidate(["S_0003"])
        text, meta = build_evidence_pack(cand, blocks, context_window=2)
        assert meta["allowed_span_ids"] == ["S_0001", "S_0002", "S_0003", "S_0004", "S_0005"]
        assert "[S_0001] text 1" in text
        assert "[S_0005] text 5" in text
        # Spans separated by blank lines.
        assert text.count("\n\n") == 4

    def test_window_clips_at_start_of_document(self):
        blocks = [_block(f"S_{i:04d}", f"text {i}") for i in range(1, 6)]
        cand = _candidate(["S_0001"])
        text, meta = build_evidence_pack(cand, blocks, context_window=2)
        # No spans before S_0001; window clips. Result has 3 spans.
        assert meta["allowed_span_ids"] == ["S_0001", "S_0002", "S_0003"]

    def test_window_clips_at_end_of_document(self):
        blocks = [_block(f"S_{i:04d}", f"text {i}") for i in range(1, 6)]
        cand = _candidate(["S_0005"])
        text, meta = build_evidence_pack(cand, blocks, context_window=2)
        assert meta["allowed_span_ids"] == ["S_0003", "S_0004", "S_0005"]


class TestMultipleMentions:
    def test_overlapping_windows_dedupe(self):
        blocks = [_block(f"S_{i:04d}", f"text {i}") for i in range(1, 8)]
        # Mentions at S_0003 and S_0004; with window=2 the union is
        # {S_0001..S_0006}.
        cand = _candidate(["S_0003", "S_0004"])
        _, meta = build_evidence_pack(cand, blocks, context_window=2)
        assert meta["allowed_span_ids"] == [
            "S_0001",
            "S_0002",
            "S_0003",
            "S_0004",
            "S_0005",
            "S_0006",
        ]

    def test_non_overlapping_windows_both_appear(self):
        blocks = [_block(f"S_{i:04d}", f"text {i}") for i in range(1, 11)]
        cand = _candidate(["S_0002", "S_0008"])
        _, meta = build_evidence_pack(cand, blocks, context_window=1)
        # Windows: {S_0001..S_0003} and {S_0007..S_0009}.
        assert meta["allowed_span_ids"] == [
            "S_0001",
            "S_0002",
            "S_0003",
            "S_0007",
            "S_0008",
            "S_0009",
        ]


class TestSectionBoundary:
    def test_window_does_not_cross_section_boundary(self):
        blocks = [
            _block("S_0001", "body 1", section_id="sec-1"),
            _block("S_0002", "body 2", section_id="sec-1"),
            _block("S_0003", "body 3", section_id="sec-1"),
            _block("S_0004", "refs 1", section_id="sec-2"),
            _block("S_0005", "refs 2", section_id="sec-2"),
        ]
        # Mention at S_0003 (sec-1); window=2 would naively include S_0004
        # and S_0005 but they're in sec-2.
        cand = _candidate(["S_0003"])
        _, meta = build_evidence_pack(cand, blocks, context_window=2)
        assert meta["allowed_span_ids"] == ["S_0001", "S_0002", "S_0003"]


class TestMeta:
    def test_meta_captures_candidate_id_and_mention(self):
        blocks = [_block("S_0001", "body")]
        cand = _candidate(["S_0001"], cid="C_042")
        _, meta = build_evidence_pack(cand, blocks, context_window=0)
        assert meta["candidate_id"] == "C_042"
        assert meta["gall_maker_mention"] == "Andricus quercuscalifornicus"


class TestErrorHandling:
    def test_unknown_span_id_raises(self):
        blocks = [_block("S_0001", "body")]
        cand = _candidate(["S_9999"])
        with pytest.raises(KeyError, match="S_9999"):
            build_evidence_pack(cand, blocks, context_window=0)
