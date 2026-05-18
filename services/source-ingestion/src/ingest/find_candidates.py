"""Find-candidates stage: high-recall gall-maker mention detection.

Calls Instructor ``n_samples`` times concurrently with a Pydantic
``response_model``; Instructor handles JSON extraction, schema validation,
and self-repair retries. Dedupes by normalized mention string; keeps
mentions that appear in ``>= agreement_threshold`` samples. Records the
per-sample call data in a flat list for the manifest accumulator.

Output: a ``CandidatesFile`` plus a list of ``ProviderCallRecord``. The
candidates carry stable ``C_NNN`` IDs and ``sample_agreement`` counts.

Per-candidate fan-out for ``extract_facts`` happens downstream over this
output.
"""

from __future__ import annotations

import asyncio
import re
import sys
import time
from typing import Literal

from pydantic import BaseModel

from ingest.llm import _provider_from_model, _safe_completion_cost, make_instructor_client
from ingest.schemas import (
    Candidate,
    CandidatesFile,
    NormalizedBlock,
    ProviderCallRecord,
)

# Stage version. Bump when stage-code changes alter outputs for the same inputs
# (dedup logic, post-processing, output fields, …). See services/source-ingestion/CLAUDE.md.
STAGE_VERSION = "1.2.0"

# Candidates whose support reduces to a single span across all samples are almost
# always comparison-table rows, bibliographic citations, or single-sentence side
# references — not species the paper treats as a subject. The find-candidates
# prompt already discourages these, but the floor catches anything the LLM lets
# through. (Nicholls 2022: 45 of 94 raw candidates had exactly one mention each,
# all literal table-row entries from the species-comparison appendix.)
MIN_MENTION_SPANS = 2


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
    generation: Literal["sexgen", "agamic", "unspecified"]


class _LLMResponse(BaseModel):
    candidates: list[_LLMCandidate]


def _normalize_mention(mention: str) -> str:
    """Normalize a gall-maker mention for dedup grouping."""
    return re.sub(r"\s+", " ", mention.strip().lower())


async def _run_one_sample(
    client,
    *,
    messages: list[dict[str, str]],
    model: str,
    prompt_sha256: str,
    total_timeout: float,
    max_retries: int,
) -> tuple[list[_LLMCandidate], ProviderCallRecord]:
    """Run one Instructor-validated sample. On any failure, return ([], error_record).

    Preserves the prior "one bad sample doesn't kill the batch" semantics.
    """
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
            f"[find-candidates] sample failed: {type(exc).__name__}: {exc}",
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
    return parsed.candidates, record


async def find_candidates(
    blocks: list[NormalizedBlock],
    model: str,
    prompt: str,
    *,
    prompt_sha256: str,
    n_samples: int = 3,
    agreement_threshold: int = 2,
    total_timeout: float = 600.0,
    max_retries: int = 2,
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
        total_timeout: per-call total timeout in seconds.
        max_retries: Instructor self-repair retry budget per sample.

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

    client = make_instructor_client()
    samples = await asyncio.gather(
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

    records = [r for _, r in samples]
    parsed_samples = [c for c, _ in samples]

    # Dedup across samples in two layers:
    #
    # 1. **Species level**: group by normalized mention. Count distinct samples
    #    contributing each species. Species below ``agreement_threshold`` are
    #    dropped entirely — they're noise.
    # 2. **Generation level**: for surviving species, emit one candidate per
    #    distinct generation any sample tagged. The species is the load-bearing
    #    signal; the generation tag is softer (LLMs disagree on it within the
    #    same paper). When at least one sample tags a specific generation
    #    (sexgen/agamic), suppress the sibling `unspecified` votes — those mean
    #    "I couldn't tell" and are uninformative when other samples could tell.
    species_groups: dict[str, dict] = {}
    for sample_idx, sample_candidates in enumerate(parsed_samples):
        species_in_sample: set[str] = set()
        for c in sample_candidates:
            mention_key = _normalize_mention(c.gall_maker_mention)
            if not mention_key:
                continue
            species_in_sample.add(mention_key)
            entry = species_groups.setdefault(
                mention_key,
                {"mention": c.gall_maker_mention, "samples": set(), "generations": {}},
            )
            gen_entry = entry["generations"].setdefault(
                c.generation, {"spans": set(), "samples": set()}
            )
            gen_entry["spans"].update(s for s in c.mention_span_ids if s in valid_span_ids)
            gen_entry["samples"].add(sample_idx)
        for k in species_in_sample:
            species_groups[k]["samples"].add(sample_idx)

    kept_species = [
        entry for entry in species_groups.values() if len(entry["samples"]) >= agreement_threshold
    ]
    kept_species.sort(key=lambda e: (-len(e["samples"]), e["mention"].lower()))

    candidates: list[Candidate] = []
    cid = 0
    dropped_single_mention = 0
    for entry in kept_species:
        gens = entry["generations"]
        # Suppress unspecified votes when any specific generation is present.
        has_specific = any(g in gens for g in ("sexgen", "agamic"))
        gen_keys = sorted(g for g in gens if not (has_specific and g == "unspecified"))
        for gen in gen_keys:
            gen_entry = gens[gen]
            if not gen_entry["spans"]:
                continue
            if len(gen_entry["spans"]) < MIN_MENTION_SPANS:
                dropped_single_mention += 1
                print(
                    f"[find-candidates] dropped {entry['mention']!r} (generation={gen}): "
                    f"{len(gen_entry['spans'])} mention span(s) < MIN_MENTION_SPANS={MIN_MENTION_SPANS}",
                    file=sys.stderr,
                )
                continue
            cid += 1
            candidates.append(
                Candidate(
                    candidate_id=f"C_{cid:03d}",
                    gall_maker_mention=entry["mention"],
                    mention_span_ids=sorted(gen_entry["spans"]),
                    sample_agreement=len(gen_entry["samples"]),
                    generation=gen,
                )
            )

    if dropped_single_mention:
        print(
            f"[find-candidates] dropped {dropped_single_mention} candidate(s) "
            f"with fewer than {MIN_MENTION_SPANS} mention spans",
            file=sys.stderr,
        )

    return CandidatesFile(candidates=candidates), records
