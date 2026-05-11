"""Find-candidates stage: high-recall gall-maker mention detection.

Calls the LLM ``n_samples`` times concurrently (via ``call_with_samples``);
parses each sample's output as JSON; dedupes by normalized mention string;
keeps mentions that appear in ``>= agreement_threshold`` samples. Records
the per-sample call data in a flat list for the manifest accumulator.

Output: a ``CandidatesFile`` plus a list of ``ProviderCallRecord``. The
candidates carry stable ``C_NNN`` IDs and ``sample_agreement`` counts.

Per-candidate fan-out for ``extract_facts`` happens downstream over this
output.
"""

from __future__ import annotations

import json
import re

from pydantic import BaseModel, ValidationError

from ingest.llm import call_with_samples
from ingest.schemas import (
    Candidate,
    CandidatesFile,
    NormalizedBlock,
    ProviderCallRecord,
)


def format_chunked_input(blocks: list[NormalizedBlock]) -> str:
    """Format normalized blocks as numbered spans for the LLM prompt.

    Output shape: ``"[S_0001] first paragraph...\\n\\n[S_0002] second..."``.

    Caller is responsible for filtering blocks to extraction-eligible
    sections; this function formats whatever it receives.
    """
    return "\n\n".join(f"[{b.span_id}] {b.text}" for b in blocks)


# Pydantic models for the LLM's expected output shape.
class _LLMCandidate(BaseModel):
    """One candidate as the LLM emits it (no candidate_id, no sample_agreement)."""

    gall_maker_mention: str
    mention_span_ids: list[str]


class _LLMResponse(BaseModel):
    candidates: list[_LLMCandidate]


def _normalize_mention(mention: str) -> str:
    """Normalize a gall-maker mention for dedup grouping."""
    return re.sub(r"\s+", " ", mention.strip().lower())


def _parse_sample(content: str) -> list[_LLMCandidate]:
    """Parse one LLM sample's content. Tolerant of empty content.

    Returns an empty list on parse failure rather than raising — one bad
    sample shouldn't kill the whole self-consistency batch.
    """
    if not content.strip():
        return []
    try:
        payload = json.loads(content)
    except json.JSONDecodeError:
        return []
    try:
        parsed = _LLMResponse.model_validate(payload)
    except ValidationError:
        return []
    return parsed.candidates


async def find_candidates(
    blocks: list[NormalizedBlock],
    model: str,
    prompt: str,
    *,
    prompt_sha256: str,
    n_samples: int = 3,
    agreement_threshold: int = 2,
    idle_timeout: float = 60.0,
    total_timeout: float = 600.0,
) -> tuple[CandidatesFile, list[ProviderCallRecord]]:
    """Detect candidate gall-maker mentions with N-way self-consistency.

    Args:
        blocks: normalized blocks restricted to extraction-eligible sections
            (caller filters first; this function does not check eligibility).
        model: LiteLLM model string.
        prompt: system-prompt content for the find-candidates stage.
        prompt_sha256: SHA-256 of the prompt file, recorded per call.
        n_samples: number of concurrent samples for self-consistency.
        agreement_threshold: keep mentions appearing in at least this many samples.
        idle_timeout / total_timeout: per-call stream timeouts.

    Returns:
        ``(CandidatesFile, list[ProviderCallRecord])`` — the CandidatesFile
        carries the deduped, agreement-filtered candidates with stable
        ``C_NNN`` IDs.
    """
    chunked_input = format_chunked_input(blocks)
    valid_span_ids = {b.span_id for b in blocks}

    messages = [
        {"role": "system", "content": prompt},
        {"role": "user", "content": chunked_input},
    ]

    samples = await call_with_samples(
        messages,
        model,
        prompt_sha256=prompt_sha256,
        n=n_samples,
        idle_timeout=idle_timeout,
        total_timeout=total_timeout,
        response_format={"type": "json_object"},
    )

    records = [r for _, r in samples]
    parsed_samples: list[list[_LLMCandidate]] = [_parse_sample(c) for c, _ in samples]

    # Dedup across samples: group by normalized mention string. For each
    # group, count how many distinct samples contributed it and union the
    # mention_span_ids. Drop span_ids not in the eligible input set.
    groups: dict[str, dict] = {}
    for sample_idx, sample_candidates in enumerate(parsed_samples):
        seen_in_sample: set[str] = set()
        for c in sample_candidates:
            key = _normalize_mention(c.gall_maker_mention)
            if not key:
                continue
            seen_in_sample.add(key)
            entry = groups.setdefault(
                key,
                {"mention": c.gall_maker_mention, "spans": set(), "samples": set()},
            )
            entry["spans"].update(s for s in c.mention_span_ids if s in valid_span_ids)
        # Record which sample each group appeared in (for agreement count).
        for k in seen_in_sample:
            groups[k]["samples"].add(sample_idx)

    # Filter by agreement threshold and assemble final candidates.
    kept = [entry for entry in groups.values() if len(entry["samples"]) >= agreement_threshold]
    # Stable ordering: by descending agreement, then alphabetical by mention.
    kept.sort(key=lambda e: (-len(e["samples"]), e["mention"].lower()))

    candidates: list[Candidate] = []
    for i, entry in enumerate(kept, start=1):
        # Skip candidates with no surviving span_ids — extract_facts has nothing
        # to work with and would abstain. Drop them quietly here.
        if not entry["spans"]:
            continue
        candidates.append(
            Candidate(
                candidate_id=f"C_{i:03d}",
                gall_maker_mention=entry["mention"],
                mention_span_ids=sorted(entry["spans"]),
                sample_agreement=len(entry["samples"]),
            )
        )

    return CandidatesFile(candidates=candidates), records
