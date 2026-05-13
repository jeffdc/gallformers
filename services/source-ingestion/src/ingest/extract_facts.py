"""Extract-facts stage: per-candidate structured fact extraction via Instructor.

For each ``Candidate`` (from find-candidates) and its associated evidence
pack, run a single Instructor call that returns a Pydantic-validated
``_LLMFacts`` object. Wrap the result in a ``GallRecord`` with stable
``record_id`` / ``candidate_id`` and return alongside a manifest record.

For Phase A, evidence ``block_id`` is typed as ``str`` (not a dynamic
``Literal[*allowed_span_ids]``) and post-hoc filtering drops evidence
citing block IDs outside the allowed set. When a cell's evidence list
becomes empty after that filtering, the cell's value is nulled and its
``support_status`` is set to ``abstained``. This keeps the contract clean
for the downstream substring gate without depending on a runtime-dynamic
Pydantic ``Literal`` (deferred to Phase B prompt-iteration).

Instructor is non-streaming here. Total-timeout discipline comes from
``asyncio.wait_for``; the idle-gap discipline used by other LLM stages
applies less here because Instructor's value is in a single validated
object, not chunk-by-chunk streaming.
"""

from __future__ import annotations

import asyncio
import time
from typing import Any

from openai.types.chat import ChatCompletionMessageParam
from pydantic import BaseModel, Field

from ingest.llm import _provider_from_model, _safe_completion_cost, make_instructor_client
from ingest.schemas import (
    Candidate,
    ConfidenceBucket,
    Evidence,
    EvidenceCell,
    GallMaker,
    GallRecord,
    GallTraits,
    Host,
    ProviderCallRecord,
    ScientificNameCell,
    SupportStatus,
    TraitCell,
)


class _LLMFacts(BaseModel):
    """Shape the LLM emits for one candidate. Subset of ``GallRecord``.

    The LLM does not assign ``record_id`` / ``candidate_id`` (we assign),
    and does not populate ``taxonomy_lookups`` (the taxonomy-lookup stage
    runs later).
    """

    gall_maker: GallMaker
    hosts: list[Host] = Field(default_factory=list)
    gall_traits: GallTraits = Field(default_factory=GallTraits)
    description: EvidenceCell | None = None
    location: EvidenceCell | None = None
    confidence_bucket: ConfidenceBucket = ConfidenceBucket.MEDIUM


def _record_id_from_candidate(candidate_id: str) -> str:
    """Map a candidate ID to its corresponding record ID (``C_001`` -> ``R_001``)."""
    num = candidate_id.rsplit("_", 1)[-1] if "_" in candidate_id else candidate_id
    return f"R_{num}"


def _abstaining_scientific_name() -> ScientificNameCell:
    """A ScientificNameCell with no value, no evidence, abstained — used when extraction fails."""
    return ScientificNameCell(
        value=None,
        evidence=[],
        support_status=SupportStatus.ABSTAINED,
        confidence=0.0,
    )


def _abstaining_record(candidate: Candidate) -> GallRecord:
    """Build an abstaining GallRecord for a candidate when extract-facts could not produce facts.

    Used when Instructor exhausts its retry budget on the schema. The record
    contract is satisfied (every required field present), but every value is
    null and every cell is marked ``ABSTAINED`` so the reviewer sees that
    the pipeline tried and gave up rather than that the source was empty.
    """
    return GallRecord(
        record_id=_record_id_from_candidate(candidate.candidate_id),
        candidate_id=candidate.candidate_id,
        gall_maker=GallMaker(scientific_name=_abstaining_scientific_name()),
        hosts=[],
        gall_traits=GallTraits(),
        description=None,
        location=None,
        confidence_bucket=ConfidenceBucket.LOW,
        warnings=[],
    )


def _filter_evidence(
    evidence: list[Evidence],
    allowed: set[str],
) -> list[Evidence]:
    """Drop evidence entries whose ``block_id`` is outside the allowed set."""
    return [e for e in evidence if e.block_id in allowed]


def _gate_cell_by_allowed(
    cell: EvidenceCell | TraitCell | ScientificNameCell,
    allowed: set[str],
) -> EvidenceCell | TraitCell | ScientificNameCell:
    """If all of a cell's evidence cites invalid block_ids, null the cell.

    Otherwise return a copy with evidence filtered to allowed entries.
    """
    if not cell.evidence:
        return cell
    kept = _filter_evidence(cell.evidence, allowed)
    if not kept:
        update: dict[str, Any] = {
            "evidence": [],
            "support_status": SupportStatus.ABSTAINED,
        }
        if isinstance(cell, TraitCell):
            update["suggested"] = []
        else:
            update["value"] = None
        return cell.model_copy(update=update)
    return cell.model_copy(update={"evidence": kept})


def _scrub_facts(facts: _LLMFacts, allowed: set[str]) -> _LLMFacts:
    """Walk all cells in the facts; drop evidence citing invalid block_ids."""
    gm = facts.gall_maker
    new_gm = gm.model_copy(
        update={
            "scientific_name": _gate_cell_by_allowed(gm.scientific_name, allowed),
            "authority": _gate_cell_by_allowed(gm.authority, allowed) if gm.authority else None,
            "rank": _gate_cell_by_allowed(gm.rank, allowed) if gm.rank else None,
            "aliases": [_gate_cell_by_allowed(a, allowed) for a in gm.aliases],
            "common_names": [_gate_cell_by_allowed(c, allowed) for c in gm.common_names],
        }
    )
    new_hosts = []
    for h in facts.hosts:
        new_hosts.append(
            h.model_copy(
                update={
                    "scientific_name": _gate_cell_by_allowed(h.scientific_name, allowed),
                    "authority": _gate_cell_by_allowed(h.authority, allowed)
                    if h.authority
                    else None,
                    "rank": _gate_cell_by_allowed(h.rank, allowed) if h.rank else None,
                }
            )
        )
    # Trait fields
    new_traits_update: dict[str, Any] = {}
    for field_name in (
        "color",
        "shape",
        "texture",
        "walls",
        "cells",
        "alignment",
        "plant_part",
        "form",
        "season",
    ):
        cell = getattr(facts.gall_traits, field_name)
        if cell is not None:
            new_traits_update[field_name] = _gate_cell_by_allowed(cell, allowed)
    if facts.gall_traits.detachable is not None:
        new_traits_update["detachable"] = _gate_cell_by_allowed(
            facts.gall_traits.detachable, allowed
        )
    new_traits = facts.gall_traits.model_copy(update=new_traits_update)

    return facts.model_copy(
        update={
            "gall_maker": new_gm,
            "hosts": new_hosts,
            "gall_traits": new_traits,
            "description": _gate_cell_by_allowed(facts.description, allowed)
            if facts.description
            else None,
            "location": _gate_cell_by_allowed(facts.location, allowed) if facts.location else None,
        }
    )


def _format_vocab_block(vocab: dict | None) -> str:
    """Render the controlled-vocab block for inclusion in the user message.

    `vocab` is the parsed schemas/gallformers-vocab.json. Returns an empty
    string when no vocab is supplied.

    Output is compact value-lists per trait field — descriptions are not
    inlined here (would balloon the prompt) but the prompt itself
    references this block and instructs the model to pick `suggested[]`
    values from these lists only.
    """
    if not vocab or "fields" not in vocab:
        return ""
    lines = ["## Controlled trait vocabulary (use only these values for `suggested[]`)\n"]
    for field, items in vocab["fields"].items():
        values = [item["value"] for item in items]
        lines.append(f"- **{field}**: {', '.join(values)}")
    return "\n".join(lines) + "\n"


def _build_messages(
    prompt: str,
    candidate: Candidate,
    evidence_pack_text: str,
    allowed: list[str],
    vocab: dict | None = None,
) -> list[ChatCompletionMessageParam]:
    """Build the chat messages for extract-facts."""
    sections = [
        "## Candidate\n",
        f"- gall_maker_mention: {candidate.gall_maker_mention}",
        f"- candidate_id: {candidate.candidate_id}",
        "",
        "## Allowed span IDs (cite only these)\n",
        ", ".join(allowed) if allowed else "(none)",
        "",
    ]
    vocab_block = _format_vocab_block(vocab)
    if vocab_block:
        sections.append(vocab_block)
    sections.append("## Evidence pack\n")
    sections.append(evidence_pack_text)
    user_content = "\n".join(sections) + "\n"
    return [
        {"role": "system", "content": prompt},
        {"role": "user", "content": user_content},
    ]


async def extract_facts(
    candidate: Candidate,
    evidence_pack_text: str,
    allowed_span_ids: list[str],
    model: str,
    prompt: str,
    *,
    prompt_sha256: str,
    total_timeout: float = 600.0,
    max_retries: int = 2,
    vocab: dict | None = None,
) -> tuple[GallRecord, ProviderCallRecord]:
    """Run extract-facts for one candidate. Returns ``(record, call_record)``.

    ``vocab`` is the parsed gallformers-vocab.json (per-field allowed
    `suggested[]` values for trait cells). When supplied, a controlled-
    vocabulary block is inlined into the user message so the model can
    pick from the closed set. When omitted, the model emits free-form
    `suggested[]` strings (which downstream tooling cannot dedupe).
    """
    messages = _build_messages(prompt, candidate, evidence_pack_text, allowed_span_ids, vocab=vocab)
    client = make_instructor_client()

    started = time.monotonic()
    try:
        facts, completion = await asyncio.wait_for(
            client.create_with_completion(
                model=model,
                messages=messages,
                response_model=_LLMFacts,
                max_retries=max_retries,
            ),
            timeout=total_timeout,
        )
    except Exception as exc:
        duration_ms = int((time.monotonic() - started) * 1000)
        return _abstaining_record(candidate), ProviderCallRecord(
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

    # Build the ProviderCallRecord from the underlying LiteLLM completion.
    usage = getattr(completion, "usage", None)
    if usage is not None:
        input_tokens = int(getattr(usage, "prompt_tokens", 0))
        output_tokens = int(getattr(usage, "completion_tokens", 0))
        usage_estimated = False
    else:
        input_tokens = output_tokens = 0
        usage_estimated = True

    record_meta = ProviderCallRecord(
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

    # Phase A: filter evidence citing block_ids outside the allowed set.
    scrubbed = _scrub_facts(facts, set(allowed_span_ids))

    record = GallRecord(
        record_id=_record_id_from_candidate(candidate.candidate_id),
        candidate_id=candidate.candidate_id,
        gall_maker=scrubbed.gall_maker,
        hosts=scrubbed.hosts,
        gall_traits=scrubbed.gall_traits,
        description=scrubbed.description,
        location=scrubbed.location,
        confidence_bucket=scrubbed.confidence_bucket,
        warnings=[],
    )
    return record, record_meta
