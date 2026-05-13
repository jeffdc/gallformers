"""Verify-claims stage: per-cell verifier from a different model family.

For each cell that survived the substring gate, ask the verifier model:
"does the quoted span text directly support this claim?" The verifier
returns one of four verdicts:

- ``supported`` — claim is directly supported by the quoted text
- ``contradicted`` — claim is contradicted by the quoted text
- ``not_enough_evidence`` — the quoted text doesn't support or contradict
- ``needs_human_review`` — verifier abstains, asks for a human

The verifier sees ONLY the field path, the claim value, and the quoted
span text. No original prompt context, no neighbor fields, no neighbor
spans. This isolation is what gives the verifier the power to disagree
with the extractor.

Best practice (per matter ``c744``): the verifier model is a different
family from the extractor (e.g. extractor Qwen + verifier DeepSeek). The
pipeline YAML configures this; this module is model-agnostic.
"""

from __future__ import annotations

import asyncio
import time
from typing import Literal

from openai.types.chat import ChatCompletionMessageParam
from pydantic import BaseModel

from ingest.llm import _provider_from_model, _safe_completion_cost, make_instructor_client
from ingest.schemas import (
    EvidenceCell,
    NormalizedBlock,
    ProviderCallRecord,
    ScientificNameCell,
    SupportStatus,
    TraitCell,
)

_VERDICT_TO_SUPPORT_STATUS: dict[str, SupportStatus] = {
    "supported": SupportStatus.SUPPORTED,
    "contradicted": SupportStatus.CONTRADICTED,
    "not_enough_evidence": SupportStatus.NOT_ENOUGH_EVIDENCE,
    "needs_human_review": SupportStatus.NEEDS_HUMAN_REVIEW,
}


class _LLMVerdict(BaseModel):
    """Verifier output. The four-value vocabulary is strict (no other values)."""

    support_status: Literal[
        "supported", "contradicted", "not_enough_evidence", "needs_human_review"
    ]
    reason: str


def _claim_string(cell: EvidenceCell | TraitCell | ScientificNameCell) -> str:
    """Render a cell's claim for the verifier prompt.

    For ``EvidenceCell``/``ScientificNameCell``, the claim is the value.
    For ``TraitCell``, the claim is the joined ``suggested`` list (the
    controlled-vocab mapping). ``original`` is the source phrase and is
    not the claim being verified.
    """
    if isinstance(cell, TraitCell):
        return ", ".join(cell.suggested) if cell.suggested else ""
    return cell.value or ""


def _quoted_text(
    cell: EvidenceCell | TraitCell | ScientificNameCell,
    blocks_by_id: dict[str, NormalizedBlock],
) -> str:
    """Concatenate the block texts referenced by the cell's evidence.

    Empty if the cell has no evidence, or if every referenced block is
    missing from the lookup map. Separator between blocks: ``\\n\\n``.
    """
    parts: list[str] = []
    for ev in cell.evidence:
        block = blocks_by_id.get(ev.block_id)
        if block is not None:
            parts.append(block.text)
    return "\n\n".join(parts)


def _build_messages(
    prompt: str,
    field_path: str,
    claim: str,
    quoted_text: str,
    record_summary: str | None = None,
) -> list[ChatCompletionMessageParam]:
    sections = []
    if record_summary:
        sections.append(f"## Record context\n\n{record_summary}")
    sections.append(f"## Field\n\n{field_path}")
    sections.append(f"## Claim\n\n{claim}")
    sections.append(f"## Quoted span text\n\n{quoted_text}")
    user_content = "\n\n".join(sections) + "\n"
    return [
        {"role": "system", "content": prompt},
        {"role": "user", "content": user_content},
    ]


async def verify_cell(
    cell: EvidenceCell | TraitCell | ScientificNameCell,
    field_path: str,
    blocks_by_id: dict[str, NormalizedBlock],
    model: str,
    prompt: str,
    *,
    prompt_sha256: str,
    total_timeout: float = 60.0,
    max_retries: int = 2,
    record_summary: str | None = None,
) -> tuple[EvidenceCell | TraitCell | ScientificNameCell, ProviderCallRecord]:
    """Run the verifier for one cell. Returns ``(updated_cell, call_record)``.

    Args:
        record_summary: optional short context string identifying the gall
            record this cell belongs to (e.g. ``"candidate species:
            Andricus assarehi"``). Lets the verifier understand which
            species the claim is being attributed to. Without it, the
            verifier sees only field_path / claim / quote and cannot
            disambiguate "is X a host of THIS species" from "is X
            mentioned anywhere."

    If the cell has no evidence (e.g. extractor abstained), the cell is
    returned unchanged and no LLM call is made — a synthetic
    ``status="skipped"``-style record is returned with zero tokens. The
    record's ``status`` is reflected in the manifest so we can audit
    which cells were verified vs skipped.
    """
    claim = _claim_string(cell)
    if not cell.evidence or not claim:
        # Nothing to verify; return unchanged with a no-op record.
        return cell, ProviderCallRecord(
            model=model,
            provider=_provider_from_model(model),
            prompt_sha256=prompt_sha256,
            input_tokens=0,
            output_tokens=0,
            cost_usd=0.0,
            duration_ms=0,
            status="ok",
        )

    quoted = _quoted_text(cell, blocks_by_id)
    messages = _build_messages(prompt, field_path, claim, quoted, record_summary)

    client = make_instructor_client()
    started = time.monotonic()
    try:
        verdict, completion = await asyncio.wait_for(
            client.create_with_completion(
                model=model,
                messages=messages,
                response_model=_LLMVerdict,
                max_retries=max_retries,
            ),
            timeout=total_timeout,
        )
    except Exception as exc:
        duration_ms = int((time.monotonic() - started) * 1000)
        # Verifier failed — cell remains in whatever support_status the extractor
        # assigned. Caller surfaces a manifest warning from the error record.
        return cell, ProviderCallRecord(
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

    new_status = _VERDICT_TO_SUPPORT_STATUS[verdict.support_status]
    updated = cell.model_copy(update={"support_status": new_status})
    return updated, call_record
