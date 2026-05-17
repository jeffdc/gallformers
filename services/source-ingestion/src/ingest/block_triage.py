"""Block-triage stage: LLM-based filter for noise blocks before preprocess.

Runs after `extract` / `ocr` and before `preprocess`. Each ``RawTextBlock`` gets
classified as ``content`` (anything the curator might care about — body prose,
abstract, methods, results, descriptions, biology, distribution, host, table
content, descriptive figure captions) or ``noise`` (running headers/footers,
standalone page numbers, table-of-contents leader-dot lines, copyright
boilerplate, plate-page artifacts, OCR garbage, etc.). Noise blocks are
dropped before any downstream stage sees them.

Voting pattern mirrors ``find_candidates``: ``n_samples`` concurrent Instructor
calls per batch, drop a block only when at least ``agreement_threshold``
samples agreed it was noise (bias toward keeping content).

This stage exists because per-publisher regexes don't scale and noisy input
trips downstream LLMs into degenerate output loops (see the May 17 Qwen3-Next
max_tokens incident on a Nicholls TOC line).
"""

from __future__ import annotations

import asyncio
import sys
import time
from typing import Literal

from pydantic import BaseModel

from ingest.concurrency import gather_bounded
from ingest.llm import _provider_from_model, _safe_completion_cost, make_instructor_client
from ingest.schemas import ProviderCallRecord, RawTextBlock

# Stage version. Bump when stage-code changes alter outputs for the same inputs.
# See services/source-ingestion/CLAUDE.md.
STAGE_VERSION = "1.3.0"


# Pydantic models for the LLM's expected output shape.
class _BlockLabel(BaseModel):
    block_id: str
    label: Literal["content", "noise"]
    reason: str | None = None


# Mirrors the pattern proven by ``find_candidates._LLMResponse``: a wrapped
# object with a single list field. Instructor's MD_JSON mode handles this
# shape reliably across providers; RootModel-of-list does not (Instructor
# strips the surrounding brackets and confuses Pydantic's JSON parser).
class _LLMResponse(BaseModel):
    labels: list[_BlockLabel]


def format_batch_input(blocks: list[RawTextBlock]) -> str:
    """Format a batch of raw blocks for the triage prompt.

    Output: ``"[<block_id>] text...\\n\\n[<block_id>] text..."``. Each block
    text is rendered verbatim — the LLM sees blocks the way downstream stages
    would see them, so its classification reflects the actual content quality.
    """
    return "\n\n".join(f"[{b.block_id}] {b.text}" for b in blocks)


async def _run_one_sample(
    client,
    *,
    messages: list[dict[str, str]],
    model: str,
    prompt_sha256: str,
    total_timeout: float,
    max_retries: int,
) -> tuple[list[_BlockLabel], ProviderCallRecord]:
    """Run one Instructor-validated triage sample. On any failure, return ([], error_record)."""
    provider = _provider_from_model(model)
    started = time.monotonic()
    try:
        parsed, completion = await asyncio.wait_for(
            client.create_with_completion(
                model=model,
                messages=messages,
                response_model=_LLMResponse,
                max_retries=max_retries,
            ),
            timeout=total_timeout,
        )
    except Exception as exc:
        duration_ms = int((time.monotonic() - started) * 1000)
        print(
            f"[block-triage] sample failed: {type(exc).__name__}: {exc}",
            file=sys.stderr,
        )
        return [], ProviderCallRecord(
            model=model,
            provider=provider,
            prompt_sha256=prompt_sha256,
            input_tokens=0,
            output_tokens=0,
            cost_usd=0.0,
            duration_ms=duration_ms,
            status="error",
            error_detail=f"{type(exc).__name__}: {exc}",
        )

    duration_ms = int((time.monotonic() - started) * 1000)
    usage = getattr(completion, "usage", None)
    if usage is not None:
        input_tokens = int(getattr(usage, "prompt_tokens", 0))
        output_tokens = int(getattr(usage, "completion_tokens", 0))
        usage_estimated = False
    else:
        input_tokens = output_tokens = 0
        usage_estimated = True

    record = ProviderCallRecord(
        model=model,
        provider=provider,
        prompt_sha256=prompt_sha256,
        input_tokens=input_tokens,
        output_tokens=output_tokens,
        cost_usd=_safe_completion_cost(model, input_tokens, output_tokens),
        duration_ms=duration_ms,
        usage_estimated=usage_estimated,
        status="ok",
    )
    return parsed.labels, record


async def _run_one_batch(
    client,
    batch: list[RawTextBlock],
    *,
    prompt: str,
    model: str,
    prompt_sha256: str,
    n_samples: int,
    total_timeout: float,
    max_retries: int,
) -> list[tuple[list[_BlockLabel], ProviderCallRecord]]:
    """Run ``n_samples`` concurrent Instructor calls for one batch of blocks."""
    batch_text = format_batch_input(batch)
    messages = [
        {"role": "system", "content": prompt},
        {"role": "user", "content": batch_text},
    ]
    return await asyncio.gather(
        *[
            _run_one_sample(
                client,
                messages=messages,
                model=model,
                prompt_sha256=prompt_sha256,
                total_timeout=total_timeout,
                max_retries=max_retries,
            )
            for _ in range(n_samples)
        ]
    )


async def triage_blocks(
    blocks: list[RawTextBlock],
    model: str,
    prompt: str,
    *,
    prompt_sha256: str,
    n_samples: int = 3,
    agreement_threshold: int = 2,
    batch_size: int = 50,
    max_concurrency: int = 5,
    total_timeout: float = 600.0,
    max_retries: int = 2,
) -> tuple[list[RawTextBlock], list[ProviderCallRecord]]:
    """Filter raw blocks through LLM triage.

    Splits ``blocks`` into batches of ``batch_size``. Batches run concurrently
    (up to ``max_concurrency`` in flight); within each batch, ``n_samples``
    Instructor calls run concurrently. A block is dropped only when at least
    ``agreement_threshold`` of those samples labeled it ``noise``; blocks with
    no votes or majority ``content`` votes are kept (bias toward preserving
    content).

    Returns:
        ``(kept_blocks, call_records)`` — ``kept_blocks`` is the input list
        minus blocks identified as noise; ``call_records`` is a flat list of
        every Instructor call's bookkeeping for the manifest accumulator.
    """
    if not blocks:
        return [], []

    client = make_instructor_client()
    valid_block_ids = {b.block_id for b in blocks}
    noise_votes: dict[str, int] = dict.fromkeys(valid_block_ids, 0)

    batches = [blocks[i : i + batch_size] for i in range(0, len(blocks), batch_size)]
    batch_results = await gather_bounded(
        [
            _run_one_batch(
                client,
                batch,
                prompt=prompt,
                model=model,
                prompt_sha256=prompt_sha256,
                n_samples=n_samples,
                total_timeout=total_timeout,
                max_retries=max_retries,
            )
            for batch in batches
        ],
        max_concurrency=max_concurrency,
    )

    all_records: list[ProviderCallRecord] = []
    for samples in batch_results:
        for labels, record in samples:
            all_records.append(record)
            # Within one sample, a block can appear at most once. Dedup defensively.
            voted_noise: set[str] = set()
            for label in labels:
                if label.block_id not in valid_block_ids:
                    continue
                if label.label == "noise":
                    voted_noise.add(label.block_id)
            for block_id in voted_noise:
                noise_votes[block_id] += 1

    kept = [b for b in blocks if noise_votes.get(b.block_id, 0) < agreement_threshold]
    return kept, all_records
