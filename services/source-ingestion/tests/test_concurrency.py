"""Tests for the shared bounded-concurrency helper."""

from __future__ import annotations

import asyncio

from ingest.concurrency import gather_bounded


class TestGatherBounded:
    async def test_preserves_input_order(self):
        async def identity(x: int) -> int:
            await asyncio.sleep(0)
            return x

        results = await gather_bounded([identity(i) for i in range(10)], max_concurrency=3)
        assert results == list(range(10))

    async def test_caps_in_flight_concurrency(self):
        """No more than ``max_concurrency`` coroutines should be running at once."""
        in_flight = 0
        peak = 0
        lock = asyncio.Lock()

        async def slow(x: int) -> int:
            nonlocal in_flight, peak
            async with lock:
                in_flight += 1
                peak = max(peak, in_flight)
            await asyncio.sleep(0.01)
            async with lock:
                in_flight -= 1
            return x

        results = await gather_bounded([slow(i) for i in range(20)], max_concurrency=3)
        assert results == list(range(20))
        assert peak <= 3, f"Expected <= 3 concurrent, observed {peak}"

    async def test_empty_input_returns_empty(self):
        results = await gather_bounded([], max_concurrency=5)
        assert results == []

    async def test_concurrency_one_runs_serially(self):
        order: list[int] = []

        async def append(x: int) -> int:
            order.append(x)
            await asyncio.sleep(0)
            return x

        await gather_bounded([append(i) for i in range(5)], max_concurrency=1)
        # With concurrency=1, scheduling is strictly sequential.
        assert order == list(range(5))
