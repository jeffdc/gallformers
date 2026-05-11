"""Async LiteLLM streaming wrapper for the north-star ingestion pipeline.

Wraps ``litellm.acompletion`` with strict timeout discipline:

- **Idle-gap timeout** — kill the stream if no chunk arrives for N seconds.
- **Total timeout** — kill the stream if total consumption exceeds N seconds.
- **One retry** on idle timeout with backoff, then fail. Stage caching at the
  pipeline level makes failure recoverable on re-run.

Every call produces a ``ProviderCallRecord`` carrying model identity, tokens,
cost, duration, and timeout indicators. The manifest accumulator collects
these per stage; failures still surface a record (via the exception's
``record`` attribute) so the manifest captures them.

For structured output (Pydantic-validated responses), callers compose with
Instructor: ``instructor.from_litellm(litellm.acompletion)``. JSON repair and
dynamic-schema construction are owned by Instructor, not this module.
"""

from __future__ import annotations

import asyncio
import time
from collections.abc import AsyncIterable
from typing import Any, Literal

import instructor
import litellm

from ingest.schemas import ProviderCallRecord

# ─── Public exceptions ─────────────────────────────────────────────────────


class IdleStreamTimeout(RuntimeError):
    """No chunk arrived from the stream within ``idle_timeout`` seconds.

    Carries the partial ``ProviderCallRecord`` so the manifest can still
    record the failure.
    """

    def __init__(self, message: str, record: ProviderCallRecord) -> None:
        super().__init__(message)
        self.record = record


class TotalStreamTimeout(RuntimeError):
    """Total stream consumption exceeded ``total_timeout`` seconds."""

    def __init__(self, message: str, record: ProviderCallRecord) -> None:
        super().__init__(message)
        self.record = record


# ─── Internals ─────────────────────────────────────────────────────────────


class _InnerIdleTimeout(Exception):
    """Internal marker for the per-chunk idle timeout.

    Distinct exception type so the outer ``asyncio.wait_for(... total_timeout)``
    can be discriminated from the inner per-chunk wait. Caught by
    ``stream_completion`` and converted to a user-facing ``IdleStreamTimeout``.
    """


async def _retry_backoff(seconds: float) -> None:
    """Wrapper around ``asyncio.sleep`` for test stubbing.

    Patching ``asyncio.sleep`` directly affects every caller globally
    (modules are shared); patching this thin shim leaves other sleeps
    in the same event loop unaffected.
    """
    await asyncio.sleep(seconds)


def _provider_from_model(model: str) -> str:
    """Extract the provider name from a LiteLLM model string.

    >>> _provider_from_model("deepinfra/Qwen/Qwen2.5-72B-Instruct")
    'deepinfra'
    >>> _provider_from_model("openai/gpt-4o")
    'openai'
    """
    if "/" in model:
        return model.split("/", 1)[0]
    return model


async def _consume_with_idle_gap(
    stream: AsyncIterable[Any],
    idle_timeout: float,
) -> tuple[str, Any]:
    """Consume an async chunk stream. Returns ``(content, usage_or_None)``.

    Raises ``_InnerIdleTimeout`` if no chunk arrives within ``idle_timeout``.
    """
    content_parts: list[str] = []
    usage: Any = None

    iterator = stream.__aiter__()
    while True:
        try:
            chunk = await asyncio.wait_for(iterator.__anext__(), timeout=idle_timeout)
        except StopAsyncIteration:
            break
        except TimeoutError as e:
            raise _InnerIdleTimeout() from e

        choices = getattr(chunk, "choices", None) or []
        if choices:
            delta = getattr(choices[0], "delta", None)
            if delta is not None:
                piece = getattr(delta, "content", None)
                if piece:
                    content_parts.append(piece)

        # With ``stream_options.include_usage=True``, the final chunk carries usage.
        chunk_usage = getattr(chunk, "usage", None)
        if chunk_usage:
            usage = chunk_usage

    return "".join(content_parts), usage


def _estimate_usage_from_text(messages: list[dict[str, str]], content: str) -> tuple[int, int]:
    """Rough fallback when the provider doesn't return usage in the terminal chunk.

    Uses ~4 chars per token. Coarse but signals ``usage_estimated=true`` in
    the record so the manifest carries the uncertainty.
    """
    input_text = "\n".join(m.get("content", "") for m in messages)
    return len(input_text) // 4, len(content) // 4


def _safe_completion_cost(model: str, input_tokens: int, output_tokens: int) -> float:
    """Best-effort cost lookup via LiteLLM's price table. ``0.0`` on failure."""
    try:
        return float(
            litellm.completion_cost(
                model=model,
                prompt_tokens=input_tokens,
                completion_tokens=output_tokens,
            )
        )
    except Exception:
        return 0.0


def _build_record(
    *,
    model: str,
    provider: str,
    prompt_sha256: str,
    content: str,
    messages: list[dict[str, str]],
    duration_ms: int,
    idle_hits: int,
    total_hit: bool,
    usage: Any,
    status: Literal["ok", "error"],
) -> ProviderCallRecord:
    """Assemble a ``ProviderCallRecord`` with usage extraction + cost lookup."""
    if usage is not None:
        input_tokens = int(getattr(usage, "prompt_tokens", 0))
        output_tokens = int(getattr(usage, "completion_tokens", 0))
        usage_estimated = False
    elif status == "ok":
        input_tokens, output_tokens = _estimate_usage_from_text(messages, content)
        usage_estimated = True
    else:
        input_tokens, output_tokens = 0, 0
        usage_estimated = False

    cost_usd = _safe_completion_cost(model, input_tokens, output_tokens)

    return ProviderCallRecord(
        model=model,
        provider=provider,
        prompt_sha256=prompt_sha256,
        input_tokens=input_tokens,
        output_tokens=output_tokens,
        cost_usd=cost_usd,
        duration_ms=duration_ms,
        idle_timeouts_hit=idle_hits,
        total_timeout_hit=total_hit,
        usage_estimated=usage_estimated,
        status=status,
    )


# ─── Public API ────────────────────────────────────────────────────────────


def make_instructor_client() -> instructor.AsyncInstructor:
    """Create an Instructor client using MD_JSON mode for provider-agnostic structured output.

    Uses ``instructor.Mode.MD_JSON`` which asks the model to return JSON in a markdown
    code block and parses it out. Requires no provider-specific API params (no
    ``tool_choice``, no ``response_format``), making it compatible across all providers
    including DeepInfra Llama.
    """
    return instructor.from_litellm(litellm.acompletion, mode=instructor.Mode.MD_JSON)


async def stream_completion(
    messages: list[dict[str, str]],
    model: str,
    *,
    prompt_sha256: str,
    idle_timeout: float = 60.0,
    total_timeout: float = 600.0,
    response_format: dict | None = None,
    retry_on_idle: bool = True,
) -> tuple[str, ProviderCallRecord]:
    """Stream a chat completion via LiteLLM with strict timeout discipline.

    Returns ``(content, record)``. The record carries model identity, tokens,
    cost, duration, and any timeout indicators.

    Args:
        messages: chat messages as ``[{"role": ..., "content": ...}, ...]``.
        model: LiteLLM model string, e.g. ``"deepinfra/Qwen/Qwen2.5-72B-Instruct"``.
        prompt_sha256: SHA-256 of the prompt-file content this call uses.
        idle_timeout: kill the stream if no chunk arrives for this many seconds.
        total_timeout: kill the stream if total consumption exceeds this many seconds.
        response_format: optional LiteLLM ``response_format`` passthrough. For
            Pydantic-validated structured output, callers should use Instructor
            (``instructor.from_litellm(acompletion)``) rather than this knob.
        retry_on_idle: on first idle timeout, sleep briefly and retry once. On
            second idle timeout, raise. Default ``True``.

    Raises:
        IdleStreamTimeout: idle-gap exceeded (after retry, if enabled).
        TotalStreamTimeout: total consumption exceeded ``total_timeout``.
        Exception: any LiteLLM error propagates (provider 4xx/5xx, etc.).
    """
    provider = _provider_from_model(model)

    kwargs: dict[str, Any] = {
        "model": model,
        "messages": messages,
        "stream": True,
        "stream_options": {"include_usage": True},
        "num_retries": 0,  # we own retries
    }
    if response_format is not None:
        kwargs["response_format"] = response_format

    async def _try_once() -> tuple[str, Any]:
        from typing import cast

        stream = await litellm.acompletion(**kwargs)
        return await _consume_with_idle_gap(cast(AsyncIterable[Any], stream), idle_timeout)

    started_at = time.monotonic()
    max_attempts = 2 if retry_on_idle else 1
    idle_hits = 0
    content = ""
    usage: Any = None

    for attempt in range(max_attempts):
        try:
            content, usage = await asyncio.wait_for(_try_once(), timeout=total_timeout)
            break
        except _InnerIdleTimeout:
            idle_hits += 1
            if attempt < max_attempts - 1:
                await _retry_backoff(1.0)
                continue
            duration_ms = int((time.monotonic() - started_at) * 1000)
            record = _build_record(
                model=model,
                provider=provider,
                prompt_sha256=prompt_sha256,
                content="",
                messages=messages,
                duration_ms=duration_ms,
                idle_hits=idle_hits,
                total_hit=False,
                usage=None,
                status="error",
            )
            raise IdleStreamTimeout(
                f"No chunk arrived within {idle_timeout}s (after {idle_hits} attempt(s))",
                record,
            ) from None
        except TimeoutError as e:
            duration_ms = int((time.monotonic() - started_at) * 1000)
            record = _build_record(
                model=model,
                provider=provider,
                prompt_sha256=prompt_sha256,
                content="",
                messages=messages,
                duration_ms=duration_ms,
                idle_hits=idle_hits,
                total_hit=True,
                usage=None,
                status="error",
            )
            raise TotalStreamTimeout(
                f"Total stream consumption exceeded {total_timeout}s",
                record,
            ) from e

    duration_ms = int((time.monotonic() - started_at) * 1000)
    record = _build_record(
        model=model,
        provider=provider,
        prompt_sha256=prompt_sha256,
        content=content,
        messages=messages,
        duration_ms=duration_ms,
        idle_hits=idle_hits,
        total_hit=False,
        usage=usage,
        status="ok",
    )
    return content, record


async def call_with_samples(
    messages: list[dict[str, str]],
    model: str,
    *,
    prompt_sha256: str,
    n: int = 3,
    idle_timeout: float = 60.0,
    total_timeout: float = 600.0,
    response_format: dict | None = None,
) -> list[tuple[str, ProviderCallRecord]]:
    """Run N concurrent ``stream_completion`` calls via ``asyncio.gather``.

    Used by ``find-candidates`` for self-consistency. Failures in individual
    samples don't fail the whole batch; the corresponding tuple has empty
    content and a record with ``status="error"``.
    """

    async def _safe_one() -> tuple[str, ProviderCallRecord]:
        try:
            return await stream_completion(
                messages,
                model,
                prompt_sha256=prompt_sha256,
                idle_timeout=idle_timeout,
                total_timeout=total_timeout,
                response_format=response_format,
            )
        except (IdleStreamTimeout, TotalStreamTimeout) as e:
            return ("", e.record)
        except Exception:
            return (
                "",
                ProviderCallRecord(
                    model=model,
                    provider=_provider_from_model(model),
                    prompt_sha256=prompt_sha256,
                    input_tokens=0,
                    output_tokens=0,
                    cost_usd=0.0,
                    duration_ms=0,
                    status="error",
                ),
            )

    return await asyncio.gather(*[_safe_one() for _ in range(n)])
