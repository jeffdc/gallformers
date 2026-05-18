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


def _candidate(
    mention_span_ids: list[str],
    cid: str = "C_001",
    mention: str = "Andricus quercuscalifornicus",
    generation: str = "unspecified",
) -> Candidate:
    return Candidate(
        candidate_id=cid,
        gall_maker_mention=mention,
        mention_span_ids=mention_span_ids,
        sample_agreement=3,
        generation=generation,
    )


class TestSiblingGenerationSpans:
    """Each candidate's pack should include the first mention span from any
    sibling-generation candidate for the same species, so species-treatment
    headers (e.g. ``"Bassettia flavipes ..., comb. nov., asexual generation"``
    that find-candidates only tagged for the agamic candidate) still appear
    in the sexgen candidate's pack — and vice versa.
    """

    def test_includes_first_mention_of_sibling_generation_candidate(self):
        blocks = [_block(f"S_{i:04d}", f"text {i}") for i in range(1, 11)]
        sexgen = _candidate(
            ["S_0007"], cid="C_001", mention="Bassettia flavipes", generation="sexgen"
        )
        agamic = _candidate(
            ["S_0002", "S_0003", "S_0004"],
            cid="C_002",
            mention="Bassettia flavipes",
            generation="agamic",
        )
        prose, meta = build_evidence_pack(sexgen, [sexgen, agamic], blocks, context_window=0)
        # sexgen's own pack would just be [S_0007]; adding agamic's first mention
        # (S_0002) at context_window=0 yields [S_0002, S_0007].
        assert meta["allowed_span_ids"] == ["S_0002", "S_0007"]

    def test_sibling_first_mention_expands_with_context_window(self):
        """The injected sibling mention also benefits from the context window."""
        blocks = [_block(f"S_{i:04d}", f"text {i}") for i in range(1, 11)]
        sexgen = _candidate(
            ["S_0008"], cid="C_001", mention="Bassettia flavipes", generation="sexgen"
        )
        agamic = _candidate(
            ["S_0002", "S_0003"], cid="C_002", mention="Bassettia flavipes", generation="agamic"
        )
        prose, meta = build_evidence_pack(sexgen, [sexgen, agamic], blocks, context_window=1)
        # Context window 1 around S_0002 → {S_0001, S_0002, S_0003}; around
        # S_0008 → {S_0007, S_0008, S_0009}.
        assert sorted(meta["allowed_span_ids"]) == [
            "S_0001",
            "S_0002",
            "S_0003",
            "S_0007",
            "S_0008",
            "S_0009",
        ]

    def test_only_unions_siblings_with_same_species_name(self):
        """Different species names → no cross-pack sharing."""
        blocks = [_block(f"S_{i:04d}", f"text {i}") for i in range(1, 11)]
        target = _candidate(
            ["S_0007"], cid="C_001", mention="Bassettia flavipes", generation="sexgen"
        )
        other_species = _candidate(
            ["S_0002"], cid="C_002", mention="Andricus balanaspis", generation="agamic"
        )
        prose, meta = build_evidence_pack(target, [target, other_species], blocks, context_window=0)
        # Different species — no sibling spans injected.
        assert meta["allowed_span_ids"] == ["S_0007"]

    def test_no_change_when_no_siblings(self):
        """A single candidate (no siblings of any kind) gets its own behavior."""
        blocks = [_block(f"S_{i:04d}", f"text {i}") for i in range(1, 11)]
        only = _candidate(
            ["S_0005"], cid="C_001", mention="Andricus solo", generation="unspecified"
        )
        prose, meta = build_evidence_pack(only, [only], blocks, context_window=0)
        assert meta["allowed_span_ids"] == ["S_0005"]


class TestSingleMention:
    def test_window_zero_yields_only_the_mention_block(self):
        blocks = [_block(f"S_{i:04d}", f"text {i}") for i in range(1, 6)]
        cand = _candidate(["S_0003"])
        prose, meta = build_evidence_pack(cand, [cand], blocks, context_window=0)
        assert meta["allowed_span_ids"] == ["S_0003"]
        assert len(prose) == 1
        assert prose[0].span_id == "S_0003"
        assert prose[0].text == "text 3"

    def test_window_two_yields_five_blocks_around_mention(self):
        blocks = [_block(f"S_{i:04d}", f"text {i}") for i in range(1, 6)]
        cand = _candidate(["S_0003"])
        prose, meta = build_evidence_pack(cand, [cand], blocks, context_window=2)
        assert meta["allowed_span_ids"] == ["S_0001", "S_0002", "S_0003", "S_0004", "S_0005"]
        assert [p.span_id for p in prose] == ["S_0001", "S_0002", "S_0003", "S_0004", "S_0005"]
        assert [p.text for p in prose] == ["text 1", "text 2", "text 3", "text 4", "text 5"]

    def test_window_clips_at_start_of_document(self):
        blocks = [_block(f"S_{i:04d}", f"text {i}") for i in range(1, 6)]
        cand = _candidate(["S_0001"])
        text, meta = build_evidence_pack(cand, [cand], blocks, context_window=2)
        # No spans before S_0001; window clips. Result has 3 spans.
        assert meta["allowed_span_ids"] == ["S_0001", "S_0002", "S_0003"]

    def test_window_clips_at_end_of_document(self):
        blocks = [_block(f"S_{i:04d}", f"text {i}") for i in range(1, 6)]
        cand = _candidate(["S_0005"])
        text, meta = build_evidence_pack(cand, [cand], blocks, context_window=2)
        assert meta["allowed_span_ids"] == ["S_0003", "S_0004", "S_0005"]


class TestMultipleMentions:
    def test_overlapping_windows_dedupe(self):
        blocks = [_block(f"S_{i:04d}", f"text {i}") for i in range(1, 8)]
        # Mentions at S_0003 and S_0004; with window=2 the union is
        # {S_0001..S_0006}.
        cand = _candidate(["S_0003", "S_0004"])
        _, meta = build_evidence_pack(cand, [cand], blocks, context_window=2)
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
        _, meta = build_evidence_pack(cand, [cand], blocks, context_window=1)
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
        _, meta = build_evidence_pack(cand, [cand], blocks, context_window=2)
        assert meta["allowed_span_ids"] == ["S_0001", "S_0002", "S_0003"]


class TestMeta:
    def test_meta_captures_candidate_id_and_mention(self):
        blocks = [_block("S_0001", "body")]
        cand = _candidate(["S_0001"], cid="C_042")
        _, meta = build_evidence_pack(cand, [cand], blocks, context_window=0)
        assert meta["candidate_id"] == "C_042"
        assert meta["gall_maker_mention"] == "Andricus quercuscalifornicus"


class TestErrorHandling:
    def test_unknown_span_id_raises(self):
        blocks = [_block("S_0001", "body")]
        cand = _candidate(["S_9999"])
        with pytest.raises(KeyError, match="S_9999"):
            build_evidence_pack(cand, [cand], blocks, context_window=0)


class TestProseSignals:
    """ProseParagraph carries per-candidate structural signals computed at
    pack-build time: absolute char offsets (for UI deep-linking), an
    is_mention flag (true when the span was a direct mention of this
    candidate), and a name_occurrences count (case-insensitive substring
    count of the candidate's name in the span text)."""

    def test_char_offsets_propagate_from_block(self):
        blocks = [
            NormalizedBlock(
                span_id="S_0001",
                block_id="S_0001",
                page=3,
                section_id="sec-1",
                char_start=120,
                char_end=180,
                text="Andricus quercuscalifornicus produces large oak apple galls.",
                raw_block_ids=["S_0001"],
            ),
        ]
        cand = _candidate(["S_0001"])
        prose, _ = build_evidence_pack(cand, [cand], blocks, context_window=0)
        assert prose[0].char_start == 120
        assert prose[0].char_end == 180

    def test_is_mention_true_only_for_candidate_mention_spans(self):
        blocks = [_block(f"S_{i:04d}", f"text {i}") for i in range(1, 6)]
        # Mention at S_0003; window=2 also pulls in S_0001, S_0002, S_0004, S_0005.
        cand = _candidate(["S_0003"])
        prose, _ = build_evidence_pack(cand, [cand], blocks, context_window=2)
        by_span = {p.span_id: p for p in prose}
        assert by_span["S_0003"].is_mention is True
        for sid in ("S_0001", "S_0002", "S_0004", "S_0005"):
            assert by_span[sid].is_mention is False, f"{sid} should not be a mention span"

    def test_name_occurrences_counts_case_insensitive_substrings(self):
        blocks = [
            _block(
                "S_0001",
                "Andricus quercuscalifornicus is large. Galls of A. quercuscalifornicus "
                "are common; ANDRICUS QUERCUSCALIFORNICUS appears in catalogs.",
            ),
            _block("S_0002", "An unrelated paragraph about Quercus alba leaves."),
            _block(
                "S_0003",
                "Two mentions: Andricus quercuscalifornicus and andricus quercuscalifornicus.",
            ),
        ]
        cand = _candidate(["S_0001"])
        prose, _ = build_evidence_pack(cand, [cand], blocks, context_window=2)
        by_span = {p.span_id: p for p in prose}
        # S_0001: 2 occurrences of full name (one is "A. quercuscalifornicus", not the
        # full "Andricus" — substring count for "Andricus quercuscalifornicus".
        assert by_span["S_0001"].name_occurrences == 2
        assert by_span["S_0002"].name_occurrences == 0
        assert by_span["S_0003"].name_occurrences == 2

    def test_is_mention_does_not_count_sibling_mention_spans(self):
        """A sibling-generation candidate's first mention is pulled into the pack
        for context, but it is not this candidate's own mention, so is_mention
        stays False. name_occurrences will pick it up via the text instead."""
        blocks = [_block(f"S_{i:04d}", f"text {i}") for i in range(1, 11)]
        sexgen = _candidate(
            ["S_0007"], cid="C_001", mention="Bassettia flavipes", generation="sexgen"
        )
        agamic = _candidate(
            ["S_0002"], cid="C_002", mention="Bassettia flavipes", generation="agamic"
        )
        prose, _ = build_evidence_pack(sexgen, [sexgen, agamic], blocks, context_window=0)
        by_span = {p.span_id: p for p in prose}
        assert by_span["S_0007"].is_mention is True  # sexgen's own
        assert by_span["S_0002"].is_mention is False  # sibling's first mention
