"""Per-candidate evidence pack builder.

Deterministic. For each candidate produced by ``find_candidates``, expand
the candidate's ``mention_span_ids`` to include ``context_window`` spans
before and after each mention (within the same section), dedupe, and sort.
The result is the closed input set the ``extract_facts`` stage sees: the
text the LLM reads and the exhaustive list of ``allowed_span_ids`` it may
cite.

Outputs are per-candidate scratch files under
``output/<src>/candidates/<candidate_id>/`` — not part of the bundle by
default. The text file is what's passed into the extract-facts prompt; the
meta JSON is what enforces the closed-set citation rule via Instructor's
dynamic Pydantic schema.
"""

from __future__ import annotations

import re
from typing import Any

from ingest.schemas import Candidate, NormalizedBlock, ProseParagraph

_WS_RE = re.compile(r"\s+")


def _normalize_mention(mention: str) -> str:
    """Normalized form of a gall-maker mention for grouping sibling candidates."""
    return _WS_RE.sub(" ", mention.strip().lower())


SPAN_SEPARATOR = "\n\n"


def format_pack_text(prose: list[ProseParagraph]) -> str:
    """Render structured prose as the ``[S_NNNN] text`` LLM-facing pack string."""
    return SPAN_SEPARATOR.join(f"[{p.span_id}] {p.text}" for p in prose)


class _BlockIndex:
    """Internal: O(1) lookups from span_id to block index, and to section_id."""

    def __init__(self, blocks: list[NormalizedBlock]) -> None:
        self.blocks = blocks
        self._by_span: dict[str, int] = {b.span_id: i for i, b in enumerate(blocks)}

    def index_of(self, span_id: str) -> int:
        if span_id not in self._by_span:
            raise KeyError(f"Span {span_id!r} not found among normalized blocks")
        return self._by_span[span_id]

    def section_of(self, span_id: str) -> str | None:
        return self.blocks[self.index_of(span_id)].section_id


def _sibling_first_mentions(candidate: Candidate, all_candidates: list[Candidate]) -> list[str]:
    """Return the first mention_span_id from each sibling-generation candidate.

    A sibling is another candidate with the same normalized ``gall_maker_mention``
    (i.e. the same species name) but a different ``candidate_id`` (typically a
    different generation tag). The first mention span of each sibling typically
    sits at the species-treatment heading or the synonyms paragraph, which
    belongs in every generation's pack regardless of which generation
    find-candidates happened to attribute it to.
    """
    norm = _normalize_mention(candidate.gall_maker_mention)
    out: list[str] = []
    for c in all_candidates:
        if c.candidate_id == candidate.candidate_id:
            continue
        if _normalize_mention(c.gall_maker_mention) != norm:
            continue
        if c.mention_span_ids:
            out.append(c.mention_span_ids[0])
    return out


def build_evidence_pack(
    candidate: Candidate,
    all_candidates: list[Candidate],
    blocks: list[NormalizedBlock],
    context_window: int = 2,
) -> tuple[list[ProseParagraph], dict[str, Any]]:
    """Build the evidence pack for one candidate as structured prose.

    Args:
        candidate: ``Candidate`` from find-candidates.
        all_candidates: full candidate list. Used to find sibling-generation
            candidates (same species name) whose first mention span gets
            unioned into this candidate's effective mentions — ensures the
            species-treatment heading appears in every generation's pack,
            even when find-candidates attributed it to only one generation.
        blocks: all normalized blocks (post-sectionize, with ``section_id``).
        context_window: number of spans before and after each mention to include.
            Defaults to 2.

    Returns:
        ``(prose, meta)`` —

        - ``prose``: ordered ``list[ProseParagraph]`` (one per selected block),
          each carrying ``span_id``, ``page``, and verbatim ``text``. Use
          ``format_pack_text(prose)`` to render the LLM-facing string.
        - ``meta``: ``{candidate_id, gall_maker_mention, allowed_span_ids[]}``.
          The ``allowed_span_ids`` list is the closed set the
          ``extract_facts`` model must cite from.

    Raises:
        KeyError: If any ``mention_span_id`` is not present in ``blocks``.
    """
    idx = _BlockIndex(blocks)

    # Effective mention spans = this candidate's own mentions plus the first
    # mention of any sibling-generation candidate (same species name).
    effective_mention_spans = list(candidate.mention_span_ids)
    effective_mention_spans.extend(_sibling_first_mentions(candidate, all_candidates))

    # Collect every block index that should appear in the pack.
    selected: set[int] = set()
    last_block_index = len(blocks) - 1
    for mention_span_id in effective_mention_spans:
        mention_idx = idx.index_of(mention_span_id)
        mention_section = idx.section_of(mention_span_id)

        # Expand ±context_window, clipping at array bounds and at section edges.
        start = max(0, mention_idx - context_window)
        end = min(last_block_index, mention_idx + context_window)
        for i in range(start, end + 1):
            if blocks[i].section_id == mention_section:
                selected.add(i)

    own_mentions = set(candidate.mention_span_ids)
    mention_lower = candidate.gall_maker_mention.lower()
    sorted_indices = sorted(selected)
    prose = [
        ProseParagraph(
            span_id=blocks[i].span_id,
            page=blocks[i].page,
            char_start=blocks[i].char_start,
            char_end=blocks[i].char_end,
            text=blocks[i].text,
            is_mention=blocks[i].span_id in own_mentions,
            name_occurrences=blocks[i].text.lower().count(mention_lower) if mention_lower else 0,
        )
        for i in sorted_indices
    ]
    meta = {
        "candidate_id": candidate.candidate_id,
        "gall_maker_mention": candidate.gall_maker_mention,
        "allowed_span_ids": [p.span_id for p in prose],
    }
    return prose, meta
