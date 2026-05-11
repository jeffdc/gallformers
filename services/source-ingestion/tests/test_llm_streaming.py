"""Tests for the async LiteLLM streaming wrapper in ingest.llm.

LiteLLM itself is mocked at the ``litellm.acompletion`` boundary; we
provide a synthetic async chunk stream so timeouts, content collection,
usage extraction, and the manifest record all run through real code paths
without hitting any real provider.
"""

from __future__ import annotations

import asyncio
from typing import Any

import pytest

from ingest.llm import (
    IdleStreamTimeout,
    TotalStreamTimeout,
    _provider_from_model,
    call_with_samples,
    stream_completion,
)

# ─── Synthetic chunk classes ──────────────────────────────────────────────


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


async def _fake_stream(chunks: list[Any], delay_per_chunk: float = 0.0):
    """Yield each chunk after an optional delay; emulates litellm's async iterator."""
    for c in chunks:
        if delay_per_chunk:
            await asyncio.sleep(delay_per_chunk)
        yield c


# ─── Provider extraction ──────────────────────────────────────────────────


class TestProviderFromModel:
    def test_extracts_first_segment(self):
        assert _provider_from_model("deepinfra/Qwen/Qwen2.5-72B-Instruct") == "deepinfra"
        assert _provider_from_model("openai/gpt-4o") == "openai"

    def test_returns_input_when_no_slash(self):
        assert _provider_from_model("gpt-4") == "gpt-4"


# ─── stream_completion: happy paths ───────────────────────────────────────


class TestStreamCompletionSuccess:
    async def test_collects_streamed_content(self, mocker):
        chunks = [
            _Chunk(content="Hel"),
            _Chunk(content="lo "),
            _Chunk(content="world."),
            _Chunk(usage=_Usage(prompt_tokens=12, completion_tokens=3)),
        ]
        mocker.patch(
            "ingest.llm.litellm.acompletion",
            return_value=_fake_stream(chunks),
        )
        mocker.patch("ingest.llm._safe_completion_cost", return_value=0.001234)

        content, record = await stream_completion(
            [{"role": "user", "content": "hi"}],
            "deepinfra/test-model",
            prompt_sha256="a" * 64,
        )

        assert content == "Hello world."
        assert record.provider == "deepinfra"
        assert record.model == "deepinfra/test-model"
        assert record.status == "ok"
        assert record.input_tokens == 12
        assert record.output_tokens == 3
        assert record.usage_estimated is False
        assert record.idle_timeouts_hit == 0
        assert record.total_timeout_hit is False
        assert record.cost_usd == pytest.approx(0.001234)

    async def test_usage_estimated_when_provider_omits_it(self, mocker):
        # No usage on the final chunk → fallback estimation kicks in.
        chunks = [_Chunk(content="hello there")]
        mocker.patch(
            "ingest.llm.litellm.acompletion",
            return_value=_fake_stream(chunks),
        )
        mocker.patch("ingest.llm._safe_completion_cost", return_value=0.0)

        content, record = await stream_completion(
            [{"role": "user", "content": "a question about something"}],
            "deepinfra/test-model",
            prompt_sha256="b" * 64,
        )

        assert content == "hello there"
        assert record.usage_estimated is True
        assert record.input_tokens > 0  # rough estimate from message text
        assert record.output_tokens > 0  # rough estimate from content


# ─── stream_completion: timeouts ──────────────────────────────────────────


class TestStreamCompletionIdleTimeout:
    async def test_idle_timeout_with_retry_then_fail(self, mocker):
        # Each attempt: a stream that sleeps longer than idle_timeout
        # before yielding anything → triggers IdleStreamTimeout.
        def _slow_stream(*a, **kw):
            return _fake_stream([_Chunk(content="x")], delay_per_chunk=0.5)

        mocker.patch("ingest.llm.litellm.acompletion", side_effect=_slow_stream)
        mocker.patch("ingest.llm._safe_completion_cost", return_value=0.0)

        # Don't actually wait 1s between attempts — patch the sleep.
        async def _no_backoff(*_a, **_kw):
            return None

        mocker.patch("ingest.llm._retry_backoff", new=_no_backoff)

        with pytest.raises(IdleStreamTimeout) as exc_info:
            await stream_completion(
                [{"role": "user", "content": "x"}],
                "deepinfra/test-model",
                prompt_sha256="c" * 64,
                idle_timeout=0.05,  # 50ms — much shorter than the 500ms delay
                total_timeout=5.0,
                retry_on_idle=True,
            )

        # Record on the raised exception captures both attempts.
        rec = exc_info.value.record
        assert rec.status == "error"
        assert rec.idle_timeouts_hit == 2
        assert rec.total_timeout_hit is False

    async def test_idle_timeout_no_retry(self, mocker):
        def _slow_stream(*a, **kw):
            return _fake_stream([_Chunk(content="x")], delay_per_chunk=0.5)

        mocker.patch("ingest.llm.litellm.acompletion", side_effect=_slow_stream)
        mocker.patch("ingest.llm._safe_completion_cost", return_value=0.0)

        with pytest.raises(IdleStreamTimeout) as exc_info:
            await stream_completion(
                [{"role": "user", "content": "x"}],
                "deepinfra/test-model",
                prompt_sha256="d" * 64,
                idle_timeout=0.05,
                total_timeout=5.0,
                retry_on_idle=False,
            )

        rec = exc_info.value.record
        assert rec.idle_timeouts_hit == 1  # no retry, single attempt

    async def test_retry_succeeds_on_second_attempt(self, mocker):
        # First call: slow stream (idle timeout). Second call: fast stream (succeeds).
        call_count = {"n": 0}

        def _streams(*a, **kw):
            call_count["n"] += 1
            if call_count["n"] == 1:
                return _fake_stream([_Chunk(content="x")], delay_per_chunk=0.5)
            return _fake_stream([_Chunk(content="ok"), _Chunk(usage=_Usage(5, 1))])

        mocker.patch("ingest.llm.litellm.acompletion", side_effect=_streams)
        mocker.patch("ingest.llm._safe_completion_cost", return_value=0.0)

        async def _no_backoff(*_a, **_kw):
            return None

        mocker.patch("ingest.llm._retry_backoff", new=_no_backoff)

        content, record = await stream_completion(
            [{"role": "user", "content": "x"}],
            "deepinfra/test-model",
            prompt_sha256="e" * 64,
            idle_timeout=0.05,
            total_timeout=5.0,
            retry_on_idle=True,
        )

        assert content == "ok"
        assert record.status == "ok"
        assert record.idle_timeouts_hit == 1  # one timeout, one retry succeeded


class TestStreamCompletionTotalTimeout:
    async def test_total_timeout_raises_distinctly(self, mocker):
        # Stream yields content slowly. With many chunks each within idle_timeout
        # but the total exceeding total_timeout, the outer wait_for fires.
        many_chunks = [_Chunk(content="x") for _ in range(50)]

        def _stream_fn(*a, **kw):
            return _fake_stream(many_chunks, delay_per_chunk=0.02)

        mocker.patch("ingest.llm.litellm.acompletion", side_effect=_stream_fn)
        mocker.patch("ingest.llm._safe_completion_cost", return_value=0.0)

        with pytest.raises(TotalStreamTimeout) as exc_info:
            await stream_completion(
                [{"role": "user", "content": "x"}],
                "deepinfra/test-model",
                prompt_sha256="f" * 64,
                idle_timeout=1.0,  # plenty per chunk
                total_timeout=0.1,  # but total is tiny
                retry_on_idle=True,
            )

        rec = exc_info.value.record
        assert rec.status == "error"
        assert rec.total_timeout_hit is True


# ─── call_with_samples ────────────────────────────────────────────────────


class TestCallWithSamples:
    async def test_runs_n_concurrent_streams(self, mocker):
        # Each call returns a different content marker so we can verify N samples.
        call_count = {"n": 0}

        def _streams(*a, **kw):
            call_count["n"] += 1
            n = call_count["n"]
            return _fake_stream([_Chunk(content=f"sample-{n}"), _Chunk(usage=_Usage(5, 2))])

        mocker.patch("ingest.llm.litellm.acompletion", side_effect=_streams)
        mocker.patch("ingest.llm._safe_completion_cost", return_value=0.0)

        results = await call_with_samples(
            [{"role": "user", "content": "x"}],
            "deepinfra/test-model",
            prompt_sha256="g" * 64,
            n=3,
        )

        assert len(results) == 3
        contents = {r[0] for r in results}
        assert contents == {"sample-1", "sample-2", "sample-3"}
        assert all(r[1].status == "ok" for r in results)

    async def test_individual_failures_are_isolated(self, mocker):
        # One call raises, the others succeed. call_with_samples must not blow up.
        call_count = {"n": 0}

        def _streams(*a, **kw):
            call_count["n"] += 1
            if call_count["n"] == 2:
                raise RuntimeError("provider 500")
            return _fake_stream(
                [_Chunk(content=f"ok-{call_count['n']}"), _Chunk(usage=_Usage(5, 1))]
            )

        mocker.patch("ingest.llm.litellm.acompletion", side_effect=_streams)
        mocker.patch("ingest.llm._safe_completion_cost", return_value=0.0)

        results = await call_with_samples(
            [{"role": "user", "content": "x"}],
            "deepinfra/test-model",
            prompt_sha256="h" * 64,
            n=3,
        )

        assert len(results) == 3
        # Two ok, one error
        statuses = [r[1].status for r in results]
        assert sorted(statuses) == ["error", "ok", "ok"]
        # The error one has empty content
        error_results = [r for r in results if r[1].status == "error"]
        assert error_results[0][0] == ""
