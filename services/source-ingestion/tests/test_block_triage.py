"""Tests for the block-triage stage.

The Instructor client is mocked at ``ingest.block_triage.make_instructor_client``
so the stage runs through real batching/voting plumbing without hitting any
provider.
"""

from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

from ingest.block_triage import _BlockLabel, _LLMResponse, triage_blocks
from ingest.schemas import RawTextBlock


def _block(block_id: str, text: str, page: int = 1) -> RawTextBlock:
    return RawTextBlock(
        block_id=block_id,
        page=page,
        text=text,
        extractor="test",
    )


def _completion(prompt_tokens: int = 10, completion_tokens: int = 5) -> SimpleNamespace:
    return SimpleNamespace(
        usage=SimpleNamespace(
            prompt_tokens=prompt_tokens,
            completion_tokens=completion_tokens,
        )
    )


def _sample(*labels: tuple) -> tuple[_LLMResponse, SimpleNamespace]:
    """Build (LLMResponse, completion) for one successful Instructor call.

    Each arg is ``(block_id, label)`` or ``(block_id, label, reason)``.
    """
    parsed = []
    for item in labels:
        if len(item) == 2:
            bid, label = item
            reason = None
        else:
            bid, label, reason = item
        parsed.append(_BlockLabel(block_id=bid, label=label, reason=reason))
    return _LLMResponse(labels=parsed), _completion()


def _mock_instructor_client(mocker, side_effects: list):
    client = MagicMock()
    client.create_with_completion = AsyncMock(side_effect=side_effects)
    mocker.patch("ingest.block_triage.make_instructor_client", return_value=client)
    return client


class TestTriageBlocks:
    async def test_drops_block_when_majority_says_noise(self, mocker):
        """2 of 3 samples say block is noise → block dropped at threshold=2."""
        blocks = [
            _block("p1-b0", "Body content."),
            _block("p1-b1", "RUNNING HEADER · 1"),
        ]
        _mock_instructor_client(
            mocker,
            [
                _sample(("p1-b0", "content"), ("p1-b1", "noise", "running header")),
                _sample(("p1-b0", "content"), ("p1-b1", "noise", "running header")),
                _sample(("p1-b0", "content"), ("p1-b1", "content")),
            ],
        )
        kept, records = await triage_blocks(
            blocks=blocks,
            model="deepinfra/test",
            prompt="p",
            prompt_sha256="a" * 64,
            n_samples=3,
            agreement_threshold=2,
            batch_size=50,
        )
        assert [b.block_id for b in kept] == ["p1-b0"]
        assert len(records) == 3
        assert all(r.status == "ok" for r in records)

    async def test_keeps_block_when_majority_says_content(self, mocker):
        """2 of 3 samples say content → block kept. Conservative default."""
        blocks = [_block("p1-b0", "Some text.")]
        _mock_instructor_client(
            mocker,
            [
                _sample(("p1-b0", "content")),
                _sample(("p1-b0", "content")),
                _sample(("p1-b0", "noise", "false positive")),
            ],
        )
        kept, _ = await triage_blocks(
            blocks=blocks,
            model="deepinfra/test",
            prompt="p",
            prompt_sha256="b" * 64,
            n_samples=3,
            agreement_threshold=2,
            batch_size=50,
        )
        assert [b.block_id for b in kept] == ["p1-b0"]

    async def test_keeps_block_when_unanimous_split(self, mocker):
        """1 noise vote alone never drops anything at threshold=2 — bias toward keeping."""
        blocks = [_block("p1-b0", "Borderline text.")]
        _mock_instructor_client(
            mocker,
            [
                _sample(("p1-b0", "content")),
                _sample(("p1-b0", "noise", "borderline")),
                _sample(("p1-b0", "content")),
            ],
        )
        kept, _ = await triage_blocks(
            blocks=blocks,
            model="deepinfra/test",
            prompt="p",
            prompt_sha256="c" * 64,
            n_samples=3,
            agreement_threshold=2,
            batch_size=50,
        )
        assert [b.block_id for b in kept] == ["p1-b0"]

    async def test_batches_blocks_into_groups(self, mocker):
        """120 blocks with batch_size=50 → 3 batches per sample → 9 calls (3 samples x 3 batches)."""
        blocks = [_block(f"p1-b{i}", f"text {i}") for i in range(120)]
        # 3 samples x 3 batches = 9 calls; each labels its batch's blocks as content.
        side_effects = []
        for _sample_idx in range(3):
            for batch_idx in range(3):
                start = batch_idx * 50
                end = min(start + 50, 120)
                side_effects.append(_sample(*[(f"p1-b{i}", "content") for i in range(start, end)]))
        _mock_instructor_client(mocker, side_effects)

        kept, records = await triage_blocks(
            blocks=blocks,
            model="deepinfra/test",
            prompt="p",
            prompt_sha256="d" * 64,
            n_samples=3,
            agreement_threshold=2,
            batch_size=50,
        )
        assert len(kept) == 120
        assert len(records) == 9

    async def test_one_bad_sample_does_not_break_voting(self, mocker):
        """A sample that errors out doesn't drop the batch — surviving samples still vote."""
        blocks = [_block("p1-b0", "Body."), _block("p1-b1", "Header · 1")]
        _mock_instructor_client(
            mocker,
            [
                Exception("instructor gave up"),
                _sample(("p1-b0", "content"), ("p1-b1", "noise", "header")),
                _sample(("p1-b0", "content"), ("p1-b1", "noise", "header")),
            ],
        )
        kept, records = await triage_blocks(
            blocks=blocks,
            model="deepinfra/test",
            prompt="p",
            prompt_sha256="e" * 64,
            n_samples=3,
            agreement_threshold=2,
            batch_size=50,
        )
        # Header dropped (2 of 2 valid samples voted noise; threshold is met).
        assert [b.block_id for b in kept] == ["p1-b0"]
        assert len(records) == 3
        statuses = sorted(r.status for r in records)
        assert statuses == ["error", "ok", "ok"]

    async def test_unlabeled_blocks_kept_by_default(self, mocker):
        """If the LLM forgets to label a block, default to keeping it (conservative)."""
        blocks = [_block("p1-b0", "First."), _block("p1-b1", "Second.")]
        _mock_instructor_client(
            mocker,
            [
                # Only labels p1-b0 in all 3 samples — p1-b1 has zero votes either way.
                _sample(("p1-b0", "content")),
                _sample(("p1-b0", "content")),
                _sample(("p1-b0", "content")),
            ],
        )
        kept, _ = await triage_blocks(
            blocks=blocks,
            model="deepinfra/test",
            prompt="p",
            prompt_sha256="f" * 64,
            n_samples=3,
            agreement_threshold=2,
            batch_size=50,
        )
        assert sorted(b.block_id for b in kept) == ["p1-b0", "p1-b1"]

    async def test_batches_run_concurrently_capped_by_max_workers(self, mocker):
        """Batches should fan out concurrently; max_workers caps in-flight calls.

        With 6 batches and max_workers=3, no more than 3 batches' calls should be
        in flight at any time. (Each batch issues n_samples calls in parallel
        internally, so this caps the BATCH parallelism.)
        """
        import asyncio

        blocks = [_block(f"p1-b{i}", f"text {i}") for i in range(300)]  # 6 batches of 50

        # Use an in-flight counter to verify the cap holds.
        in_flight = 0
        peak = 0
        lock = asyncio.Lock()

        async def _slow_response(*args, **kwargs):
            nonlocal in_flight, peak
            async with lock:
                in_flight += 1
                peak = max(peak, in_flight)
            await asyncio.sleep(0.01)
            async with lock:
                in_flight -= 1
            # Return a successful response labeling everything as content.
            return _sample(*[(f"p1-b{i}", "content") for i in range(300)])

        client = MagicMock()
        client.create_with_completion = AsyncMock(side_effect=_slow_response)
        mocker.patch("ingest.block_triage.make_instructor_client", return_value=client)

        kept, records = await triage_blocks(
            blocks=blocks,
            model="deepinfra/test",
            prompt="p",
            prompt_sha256="m" * 64,
            n_samples=3,
            agreement_threshold=2,
            batch_size=50,
            max_concurrency=3,
        )
        # 6 batches x 3 samples = 18 calls total.
        assert len(records) == 18
        # Concurrency cap: at most max_concurrency batches x n_samples = 3 x 3 = 9 in flight.
        assert peak <= 9, f"Expected <= 9 in flight, observed {peak}"
        # All blocks kept since every sample said content.
        assert len(kept) == 300

    async def test_empty_input_returns_empty(self, mocker):
        """No blocks in → no blocks out, no LLM calls."""
        _mock_instructor_client(mocker, [])
        kept, records = await triage_blocks(
            blocks=[],
            model="deepinfra/test",
            prompt="p",
            prompt_sha256="g" * 64,
            n_samples=3,
            agreement_threshold=2,
            batch_size=50,
        )
        assert kept == []
        assert records == []
