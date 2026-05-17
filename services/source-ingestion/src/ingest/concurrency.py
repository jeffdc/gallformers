"""Shared async helpers for pipeline stages that fan out concurrent LLM / API calls.

Several stages (``extract_facts``, ``verify_claims``, ``block_triage``, …)
all need the same pattern: a list of coroutines should be awaited
concurrently, but with a ceiling on how many are in flight at once
(to respect per-provider concurrency caps and to avoid hammering free
file descriptors / sockets). This module is the single home for that.
"""

from __future__ import annotations

import asyncio
from collections.abc import Awaitable, Iterable


async def gather_bounded[T](
    coros: Iterable[Awaitable[T]],
    *,
    max_concurrency: int,
) -> list[T]:
    """Run coroutines concurrently with at most ``max_concurrency`` in flight.

    Result order matches input order (same contract as ``asyncio.gather``).
    Empty input returns an empty list without spawning any tasks.

    Use this instead of an inline ``Semaphore`` + ``gather`` pattern in
    individual stage modules — single source of truth keeps the concurrency
    rule consistent across stages.
    """
    if max_concurrency < 1:
        raise ValueError(f"max_concurrency must be >= 1, got {max_concurrency}")

    semaphore = asyncio.Semaphore(max_concurrency)

    async def _bounded(coro: Awaitable[T]) -> T:
        async with semaphore:
            return await coro

    return await asyncio.gather(*[_bounded(c) for c in coros])
