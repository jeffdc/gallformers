"""Tests for the find-candidates stage.

LiteLLM is mocked at ``ingest.llm.litellm.acompletion`` so the stage runs
through real ``call_with_samples`` plumbing without hitting any provider.
"""

from __future__ import annotations

import json

from ingest.find_candidates import (
    _normalize_mention,
    _parse_sample,
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


# ─── Synthetic chunk classes (mirror those in test_llm_streaming) ─────────


class _Delta:
    def __init__(self, content: str | None) -> None:
        self.content = content


class _Choice:
    def __init__(self, content: str | None) -> None:
        self.delta = _Delta(content)


class _Usage:
    def __init__(self, prompt_tokens: int, completion_tokens: int) -> None:
        self.prompt_tokens = prompt_tokens
        self.completion_tokens = completion_tokens


class _Chunk:
    def __init__(self, content: str | None = None, usage: _Usage | None = None) -> None:
        self.choices = [_Choice(content)] if content is not None else []
        self.usage = usage


async def _fake_stream(chunks):
    for c in chunks:
        yield c


def _stream_with_payload(payload: dict) -> object:
    """Build a fake stream that yields one content chunk with JSON, then usage."""
    content = json.dumps(payload)
    return _fake_stream([_Chunk(content=content), _Chunk(usage=_Usage(10, 5))])


# ─── Pure-function tests ──────────────────────────────────────────────────


class TestFormatChunkedInput:
    def test_renders_numbered_spans(self):
        blocks = [_block("S_0001", "first"), _block("S_0002", "second")]
        out = format_chunked_input(blocks)
        assert out == "[S_0001] first\n\n[S_0002] second"


class TestNormalizeMention:
    def test_lowercases_and_collapses_whitespace(self):
        assert _normalize_mention("  Andricus   QUERCUS  ") == "andricus quercus"


class TestParseSample:
    def test_valid_response_parses(self):
        content = json.dumps(
            {"candidates": [{"gall_maker_mention": "X", "mention_span_ids": ["S_0001"]}]}
        )
        parsed = _parse_sample(content)
        assert len(parsed) == 1
        assert parsed[0].gall_maker_mention == "X"

    def test_empty_string_yields_empty(self):
        assert _parse_sample("") == []
        assert _parse_sample("   ") == []

    def test_malformed_json_yields_empty(self):
        assert _parse_sample("not json") == []

    def test_wrong_shape_yields_empty(self):
        # Right JSON, wrong schema — no "candidates" key.
        assert _parse_sample('{"foo": "bar"}') == []


# ─── Stage integration tests ──────────────────────────────────────────────


class TestFindCandidates:
    async def test_agreement_threshold_filters_singletons(self, mocker):
        blocks = [_block("S_0001", "Andricus quercuscalifornicus paragraph.")]

        # 3 samples: two agree on the same mention; one is a one-off.
        sample_payloads = [
            {
                "candidates": [
                    {
                        "gall_maker_mention": "Andricus quercuscalifornicus",
                        "mention_span_ids": ["S_0001"],
                    }
                ]
            },
            {
                "candidates": [
                    {
                        "gall_maker_mention": "Andricus quercuscalifornicus",
                        "mention_span_ids": ["S_0001"],
                    }
                ]
            },
            {
                "candidates": [
                    {"gall_maker_mention": "Phylloxera quercus", "mention_span_ids": ["S_0001"]}
                ]
            },
        ]
        streams = iter([_stream_with_payload(p) for p in sample_payloads])
        mocker.patch("ingest.llm.litellm.acompletion", side_effect=lambda **kw: next(streams))
        mocker.patch("ingest.llm._safe_completion_cost", return_value=0.0)

        candidates_file, records = await find_candidates(
            blocks=blocks,
            model="deepinfra/test",
            prompt="find candidates prompt",
            prompt_sha256="a" * 64,
            n_samples=3,
            agreement_threshold=2,
        )

        assert len(records) == 3
        # Only the agreed-on mention survives.
        assert len(candidates_file.candidates) == 1
        c = candidates_file.candidates[0]
        assert c.candidate_id == "C_001"
        assert c.gall_maker_mention == "Andricus quercuscalifornicus"
        assert c.mention_span_ids == ["S_0001"]
        assert c.sample_agreement == 2

    async def test_dedup_by_normalized_mention(self, mocker):
        blocks = [_block("S_0001", "x"), _block("S_0002", "y")]

        # Same name spelled differently across samples (whitespace + case).
        sample_payloads = [
            {
                "candidates": [
                    {"gall_maker_mention": "Andricus californicus", "mention_span_ids": ["S_0001"]}
                ]
            },
            {
                "candidates": [
                    {
                        "gall_maker_mention": "  ANDRICUS  CALIFORNICUS  ",
                        "mention_span_ids": ["S_0002"],
                    }
                ]
            },
            {
                "candidates": [
                    {"gall_maker_mention": "Andricus californicus", "mention_span_ids": ["S_0002"]}
                ]
            },
        ]
        streams = iter([_stream_with_payload(p) for p in sample_payloads])
        mocker.patch("ingest.llm.litellm.acompletion", side_effect=lambda **kw: next(streams))
        mocker.patch("ingest.llm._safe_completion_cost", return_value=0.0)

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
        sample_payloads = [
            {"candidates": [{"gall_maker_mention": "Foo bar", "mention_span_ids": ["S_9999"]}]},
        ] * 3
        streams = iter([_stream_with_payload(p) for p in sample_payloads])
        mocker.patch("ingest.llm.litellm.acompletion", side_effect=lambda **kw: next(streams))
        mocker.patch("ingest.llm._safe_completion_cost", return_value=0.0)

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

    async def test_one_bad_sample_does_not_break_others(self, mocker):
        blocks = [_block("S_0001", "x")]

        bad_stream = _fake_stream([_Chunk(content="not json"), _Chunk(usage=_Usage(5, 1))])
        good_payload = {
            "candidates": [{"gall_maker_mention": "Foo", "mention_span_ids": ["S_0001"]}]
        }
        streams = iter(
            [bad_stream, _stream_with_payload(good_payload), _stream_with_payload(good_payload)]
        )
        mocker.patch("ingest.llm.litellm.acompletion", side_effect=lambda **kw: next(streams))
        mocker.patch("ingest.llm._safe_completion_cost", return_value=0.0)

        candidates_file, records = await find_candidates(
            blocks=blocks,
            model="deepinfra/test",
            prompt="p",
            prompt_sha256="d" * 64,
            n_samples=3,
            agreement_threshold=2,
        )
        # All three samples produced records (one parse-failed); two valid
        # samples agreed on "Foo".
        assert len(records) == 3
        assert len(candidates_file.candidates) == 1
        assert candidates_file.candidates[0].gall_maker_mention == "Foo"
        assert candidates_file.candidates[0].sample_agreement == 2
