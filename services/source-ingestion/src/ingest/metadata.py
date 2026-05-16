"""Metadata stage: evidence-bound bibliographic extraction via Instructor.

Reads the first few sections (title, abstract, introduction by convention)
and produces a ``DocumentMetadata`` — title, authors, year, journal, DOI,
etc. — each as an ``EvidenceCell`` with citations into the input spans.

This stage is intentionally separate from ``extract_facts``. Bibliographic
metadata is orthogonal to per-record gall-host facts, and folding both
into one prompt would make the already-hard fact-extraction job harder.

Like ``extract_facts``, this uses Instructor (non-streaming) with a static
Pydantic schema. Span-id scrubbing happens post-hoc: evidence citing
block_ids outside the allowed set is dropped; cells whose evidence
becomes empty are nulled and marked ``abstained``.
"""

from __future__ import annotations

import asyncio
import time

from openai.types.chat import ChatCompletionMessageParam

# Reuse the same span-id scrubbing logic from extract_facts.
from ingest.extract_facts import _gate_cell_by_allowed
from ingest.find_candidates import format_chunked_input
from ingest.llm import _provider_from_model, _safe_completion_cost, make_instructor_client
from ingest.schemas import (
    DocumentMetadata,
    EvidenceCell,
    NormalizedBlock,
    ProviderCallRecord,
    SupportStatus,
)


def _scrub_metadata(metadata: DocumentMetadata, allowed: set[str]) -> DocumentMetadata:
    """Filter evidence in every cell of the metadata to the allowed span set."""

    def _maybe(cell: EvidenceCell | None) -> EvidenceCell | None:
        return _gate_cell_by_allowed(cell, allowed) if cell is not None else None  # type: ignore[return-value]

    return metadata.model_copy(
        update={
            "title": _gate_cell_by_allowed(metadata.title, allowed),
            "authors": [_gate_cell_by_allowed(a, allowed) for a in metadata.authors],
            "year": _maybe(metadata.year),
            "journal": _maybe(metadata.journal),
            "volume": _maybe(metadata.volume),
            "issue": _maybe(metadata.issue),
            "pages": _maybe(metadata.pages),
            "doi": _maybe(metadata.doi),
            "language": _maybe(metadata.language),
        }
    )


def _abstaining_title() -> EvidenceCell:
    """Title is required on DocumentMetadata; on total LLM failure we abstain."""
    return EvidenceCell(
        value=None,
        evidence=[],
        support_status=SupportStatus.ABSTAINED,
        confidence=0.0,
    )


def _build_messages(
    prompt: str, chunked_input: str, allowed: list[str]
) -> list[ChatCompletionMessageParam]:
    user_content = (
        f"## Allowed span IDs (cite only these)\n\n"
        f"{', '.join(allowed) if allowed else '(none)'}\n\n"
        f"## Document spans\n\n"
        f"{chunked_input}\n"
    )
    return [
        {"role": "system", "content": prompt},
        {"role": "user", "content": user_content},
    ]


async def extract_document_metadata(
    blocks: list[NormalizedBlock],
    model: str,
    prompt: str,
    *,
    prompt_sha256: str,
    total_timeout: float = 60.0,
    max_retries: int = 2,
) -> tuple[DocumentMetadata, ProviderCallRecord]:
    """Run metadata extraction over the supplied blocks.

    Caller is responsible for filtering ``blocks`` to the relevant section
    types (typically title/abstract/introduction). This function takes
    whatever spans it receives and asks the LLM for evidence-bound
    bibliographic metadata.

    On empty input, returns a metadata object that abstains everywhere
    and a synthetic zero-cost record. The pipeline can still assemble.
    """
    if not blocks:
        return DocumentMetadata(title=_abstaining_title()), ProviderCallRecord(
            model=model,
            provider=_provider_from_model(model),
            prompt_sha256=prompt_sha256,
            input_tokens=0,
            output_tokens=0,
            cost_usd=0.0,
            duration_ms=0,
            status="ok",
        )

    chunked_input = format_chunked_input(blocks)
    allowed = [b.span_id for b in blocks]
    messages = _build_messages(prompt, chunked_input, allowed)

    client = make_instructor_client()
    started = time.monotonic()
    try:
        metadata, completion = await asyncio.wait_for(
            client.create_with_completion(
                model=model,
                messages=messages,
                response_model=DocumentMetadata,
                max_retries=max_retries,
            ),
            timeout=total_timeout,
        )
    except Exception as exc:
        duration_ms = int((time.monotonic() - started) * 1000)
        return DocumentMetadata(title=_abstaining_title()), ProviderCallRecord(
            model=model,
            provider=_provider_from_model(model),
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

    call_record = ProviderCallRecord(
        model=model,
        provider=_provider_from_model(model),
        prompt_sha256=prompt_sha256,
        input_tokens=input_tokens,
        output_tokens=output_tokens,
        cost_usd=_safe_completion_cost(model, input_tokens, output_tokens),
        duration_ms=duration_ms,
        usage_estimated=usage_estimated,
        status="ok",
    )

    scrubbed = _scrub_metadata(metadata, set(allowed))
    return scrubbed, call_record
