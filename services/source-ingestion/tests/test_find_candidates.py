"""Tests for the find-candidates stage.

The Instructor client is mocked at ``ingest.find_candidates.make_instructor_client``
so the stage runs through real dedup/agreement plumbing without hitting any
provider.
"""

from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

from ingest.find_candidates import (
    _LLMCandidate,
    _LLMResponse,
    _normalize_mention,
    find_candidates,
    format_chunked_input,
)
from ingest.schemas import NormalizedBlock


def _block(span_id: str, text: str, section_id: str = "sec-1") -> NormalizedBlock:
    return NormalizedBlock(
        span_id=span_id,
        block_id=span_id,
        page=1,
        section_id=section_id,
        char_start=0,
        char_end=len(text),
        text=text,
        raw_block_ids=[span_id],
    )


def _completion(prompt_tokens: int = 10, completion_tokens: int = 5) -> SimpleNamespace:
    """Stand-in completion object with the .usage attributes _run_one_sample reads."""
    return SimpleNamespace(
        usage=SimpleNamespace(
            prompt_tokens=prompt_tokens,
            completion_tokens=completion_tokens,
        )
    )


def _ok_sample(*mentions_with_spans: tuple) -> tuple[_LLMResponse, SimpleNamespace]:
    """Build an (LLMResponse, completion) pair for one successful Instructor call.

    Each arg is ``(mention_text, [span_ids])`` or
    ``(mention_text, [span_ids], generation)``. When the generation slot is
    omitted, it defaults to ``"unspecified"``.
    """
    candidates = []
    for item in mentions_with_spans:
        if len(item) == 2:
            mention, spans = item
            gen = "unspecified"
        else:
            mention, spans, gen = item
        candidates.append(
            _LLMCandidate(gall_maker_mention=mention, mention_span_ids=spans, generation=gen)
        )
    return _LLMResponse(candidates=candidates), _completion()


def _mock_instructor_client(mocker, side_effects: list):
    """Patch make_instructor_client to return a client whose create_with_completion
    yields the supplied side_effects (one per sample).
    """
    client = MagicMock()
    client.create_with_completion = AsyncMock(side_effect=side_effects)
    mocker.patch("ingest.find_candidates.make_instructor_client", return_value=client)
    return client


# ─── Pure-function tests ──────────────────────────────────────────────────


class TestFormatChunkedInput:
    def test_renders_numbered_spans(self):
        blocks = [_block("S_0001", "first"), _block("S_0002", "second")]
        out = format_chunked_input(blocks)
        assert out == "[S_0001] first\n\n[S_0002] second"


class TestNormalizeMention:
    def test_lowercases_and_collapses_whitespace(self):
        assert _normalize_mention("  Andricus   QUERCUS  ") == "andricus quercus"


# ─── Stage integration tests ──────────────────────────────────────────────


class TestFindCandidates:
    async def test_agreement_threshold_filters_singletons(self, mocker):
        blocks = [
            _block("S_0001", "Andricus quercuscalifornicus paragraph."),
            _block("S_0002", "Continuation."),
        ]

        # 3 samples: two agree on the same mention; one is a one-off.
        _mock_instructor_client(
            mocker,
            [
                _ok_sample(("Andricus quercuscalifornicus", ["S_0001", "S_0002"])),
                _ok_sample(("Andricus quercuscalifornicus", ["S_0001", "S_0002"])),
                _ok_sample(("Phylloxera quercus", ["S_0001", "S_0002"])),
            ],
        )

        candidates_file, records = await find_candidates(
            blocks=blocks,
            model="deepinfra/test",
            prompt="find candidates prompt",
            prompt_sha256="a" * 64,
            n_samples=3,
            agreement_threshold=2,
        )

        assert len(records) == 3
        assert all(r.status == "ok" for r in records)
        # Only the agreed-on mention survives.
        assert len(candidates_file.candidates) == 1
        c = candidates_file.candidates[0]
        assert c.candidate_id == "C_001"
        assert c.gall_maker_mention == "Andricus quercuscalifornicus"
        assert c.mention_span_ids == ["S_0001", "S_0002"]
        assert c.sample_agreement == 2

    async def test_dedup_by_normalized_mention(self, mocker):
        blocks = [_block("S_0001", "x"), _block("S_0002", "y")]

        # Same name spelled differently across samples (whitespace + case).
        _mock_instructor_client(
            mocker,
            [
                _ok_sample(("Andricus californicus", ["S_0001"])),
                _ok_sample(("  ANDRICUS  CALIFORNICUS  ", ["S_0002"])),
                _ok_sample(("Andricus californicus", ["S_0002"])),
            ],
        )

        candidates_file, _ = await find_candidates(
            blocks=blocks,
            model="deepinfra/test",
            prompt="p",
            prompt_sha256="b" * 64,
            n_samples=3,
            agreement_threshold=2,
        )

        assert len(candidates_file.candidates) == 1
        c = candidates_file.candidates[0]
        assert c.sample_agreement == 3
        # Union of mention_span_ids across samples; sorted.
        assert c.mention_span_ids == ["S_0001", "S_0002"]

    async def test_invalid_span_ids_dropped(self, mocker):
        blocks = [_block("S_0001", "x")]

        # All 3 samples cite a span that doesn't exist.
        _mock_instructor_client(
            mocker,
            [
                _ok_sample(("Foo bar", ["S_9999"])),
                _ok_sample(("Foo bar", ["S_9999"])),
                _ok_sample(("Foo bar", ["S_9999"])),
            ],
        )

        candidates_file, _ = await find_candidates(
            blocks=blocks,
            model="deepinfra/test",
            prompt="p",
            prompt_sha256="c" * 64,
            n_samples=3,
            agreement_threshold=2,
        )
        # Candidate had agreement=3 but no valid span_ids → dropped.
        assert candidates_file.candidates == []

    async def test_species_threshold_lets_minority_generation_survive(self, mocker):
        """Species-level agreement (not (species,gen)-level) decides survival.

        2 of 3 samples say (X, sexgen); 1 of 3 says (X, agamic). The species is
        unambiguous (3/3) so BOTH generations should be emitted as candidates,
        even though the agamic tag only appears in one sample.
        """
        blocks = [
            _block("S_0001", "sexgen passage 1"),
            _block("S_0002", "sexgen passage 2"),
            _block("S_0003", "agamic passage 1"),
            _block("S_0004", "agamic passage 2"),
        ]

        _mock_instructor_client(
            mocker,
            [
                _ok_sample(("Acraspis quercushirta", ["S_0001", "S_0002"], "sexgen")),
                _ok_sample(("Acraspis quercushirta", ["S_0001", "S_0002"], "sexgen")),
                _ok_sample(("Acraspis quercushirta", ["S_0003", "S_0004"], "agamic")),
            ],
        )

        candidates_file, _ = await find_candidates(
            blocks=blocks,
            model="deepinfra/test",
            prompt="p",
            prompt_sha256="x" * 64,
            n_samples=3,
            agreement_threshold=2,
        )

        by_gen = {c.generation: c for c in candidates_file.candidates}
        assert set(by_gen.keys()) == {"sexgen", "agamic"}
        assert by_gen["sexgen"].sample_agreement == 2
        assert by_gen["agamic"].sample_agreement == 1
        assert by_gen["sexgen"].mention_span_ids == ["S_0001", "S_0002"]
        assert by_gen["agamic"].mention_span_ids == ["S_0003", "S_0004"]

    async def test_specific_generation_drops_unspecified_votes(self, mocker):
        """When any sample tags a specific generation, drop sibling unspecified votes.

        unspecified means 'I couldn't tell.' If other samples could tell, the
        unspecified vote is the uninformative one — don't emit it.
        """
        blocks = [_block("S_0001", "content"), _block("S_0002", "more content")]

        _mock_instructor_client(
            mocker,
            [
                _ok_sample(("Andricus sp", ["S_0001", "S_0002"], "sexgen")),
                _ok_sample(("Andricus sp", ["S_0001", "S_0002"], "unspecified")),
                _ok_sample(("Andricus sp", ["S_0001", "S_0002"], "sexgen")),
            ],
        )

        candidates_file, _ = await find_candidates(
            blocks=blocks,
            model="deepinfra/test",
            prompt="p",
            prompt_sha256="y" * 64,
            n_samples=3,
            agreement_threshold=2,
        )

        # Only the sexgen candidate; unspecified is suppressed.
        assert len(candidates_file.candidates) == 1
        assert candidates_file.candidates[0].generation == "sexgen"

    async def test_dedup_keys_on_mention_and_generation_separately(self, mocker):
        """Same mention with different generation produces two distinct candidates.

        When a paper describes both biological generations of one species in
        separately identifiable passages, find-candidates must emit two
        candidates rather than collapsing them by name alone.
        """
        blocks = [
            _block("S_0001", "sexual gen part 1"),
            _block("S_0002", "sexual gen part 2"),
            _block("S_0003", "agamic gen part 1"),
            _block("S_0004", "agamic gen part 2"),
        ]

        _mock_instructor_client(
            mocker,
            [
                _ok_sample(
                    ("Andricus balanaspis", ["S_0001", "S_0002"], "sexgen"),
                    ("Andricus balanaspis", ["S_0003", "S_0004"], "agamic"),
                ),
                _ok_sample(
                    ("Andricus balanaspis", ["S_0001", "S_0002"], "sexgen"),
                    ("Andricus balanaspis", ["S_0003", "S_0004"], "agamic"),
                ),
                _ok_sample(
                    ("Andricus balanaspis", ["S_0001", "S_0002"], "sexgen"),
                    ("Andricus balanaspis", ["S_0003", "S_0004"], "agamic"),
                ),
            ],
        )

        candidates_file, _ = await find_candidates(
            blocks=blocks,
            model="deepinfra/test",
            prompt="p",
            prompt_sha256="e" * 64,
            n_samples=3,
            agreement_threshold=2,
        )

        assert len(candidates_file.candidates) == 2
        by_gen = {c.generation: c for c in candidates_file.candidates}
        assert set(by_gen.keys()) == {"sexgen", "agamic"}
        assert by_gen["sexgen"].gall_maker_mention == "Andricus balanaspis"
        assert by_gen["agamic"].gall_maker_mention == "Andricus balanaspis"
        assert by_gen["sexgen"].mention_span_ids == ["S_0001", "S_0002"]
        assert by_gen["agamic"].mention_span_ids == ["S_0003", "S_0004"]
        assert by_gen["sexgen"].sample_agreement == 3
        assert by_gen["agamic"].sample_agreement == 3

    async def test_single_mention_candidates_dropped(self, mocker):
        """Candidates whose only support is a single mention span are dropped.

        Real species treatments produce multiple mentions: a treatment header,
        diagnosis, biology, etc. A single mention is almost always a
        comparison-table row, a citation, or a side reference. (Nicholls 2022
        ran 94 candidates → 45 of them had exactly one mention each, all
        literal table-row entries from the species-comparison appendix.)"""
        blocks = [_block("S_0001", "x"), _block("S_0002", "y"), _block("S_0003", "z")]

        # Three samples all agree on a single-mention candidate.
        _mock_instructor_client(
            mocker,
            [
                _ok_sample(("Andricus passing", ["S_0001"])),
                _ok_sample(("Andricus passing", ["S_0001"])),
                _ok_sample(("Andricus passing", ["S_0001"])),
            ],
        )
        candidates_file, _ = await find_candidates(
            blocks=blocks,
            model="deepinfra/test",
            prompt="p",
            prompt_sha256="e" * 64,
            n_samples=3,
            agreement_threshold=2,
        )
        assert candidates_file.candidates == []

    async def test_multi_mention_candidates_kept(self, mocker):
        """Candidates with two or more mention spans clear the filter."""
        blocks = [_block("S_0001", "x"), _block("S_0002", "y"), _block("S_0003", "z")]
        _mock_instructor_client(
            mocker,
            [
                _ok_sample(("Andricus real", ["S_0001", "S_0002"])),
                _ok_sample(("Andricus real", ["S_0001", "S_0002"])),
                _ok_sample(("Andricus real", ["S_0001", "S_0002"])),
            ],
        )
        candidates_file, _ = await find_candidates(
            blocks=blocks,
            model="deepinfra/test",
            prompt="p",
            prompt_sha256="f" * 64,
            n_samples=3,
            agreement_threshold=2,
        )
        assert len(candidates_file.candidates) == 1
        assert candidates_file.candidates[0].mention_span_ids == ["S_0001", "S_0002"]

    async def test_one_bad_sample_does_not_break_others(self, mocker):
        blocks = [_block("S_0001", "x"), _block("S_0002", "y")]

        # First sample raises (simulating Instructor giving up after max_retries);
        # other two succeed with the same mention.
        _mock_instructor_client(
            mocker,
            [
                Exception("instructor validation failed after retries"),
                _ok_sample(("Foo", ["S_0001", "S_0002"])),
                _ok_sample(("Foo", ["S_0001", "S_0002"])),
            ],
        )

        candidates_file, records = await find_candidates(
            blocks=blocks,
            model="deepinfra/test",
            prompt="p",
            prompt_sha256="d" * 64,
            n_samples=3,
            agreement_threshold=2,
        )
        # All three samples produced records (one with status="error"); two
        # valid samples agreed on "Foo".
        assert len(records) == 3
        statuses = sorted(r.status for r in records)
        assert statuses == ["error", "ok", "ok"]
        assert len(candidates_file.candidates) == 1
        assert candidates_file.candidates[0].gall_maker_mention == "Foo"
        assert candidates_file.candidates[0].sample_agreement == 2
