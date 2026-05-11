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

from typing import Any

from ingest.schemas import Candidate, NormalizedBlock

SPAN_SEPARATOR = "\n\n"


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


def build_evidence_pack(
    candidate: Candidate,
    blocks: list[NormalizedBlock],
    context_window: int = 2,
) -> tuple[str, dict[str, Any]]:
    """Build the evidence pack for one candidate.

    Args:
        candidate: ``Candidate`` from find-candidates.
        blocks: all normalized blocks (post-sectionize, with ``section_id``).
        context_window: number of spans before and after each mention to include.
            Defaults to 2.

    Returns:
        ``(text, meta)`` —

        - ``text``: numbered-span concatenation in the form
          ``"[S_0033] ...\\n\\n[S_0034] ...\\n\\n[S_0035] ..."``.
        - ``meta``: ``{candidate_id, gall_maker_mention, allowed_span_ids[]}``.
          The ``allowed_span_ids`` list is the closed set the
          ``extract_facts`` model must cite from.

    Raises:
        KeyError: If any ``mention_span_id`` is not present in ``blocks``.
    """
    idx = _BlockIndex(blocks)

    # Collect every block index that should appear in the pack.
    selected: set[int] = set()
    last_block_index = len(blocks) - 1
    for mention_span_id in candidate.mention_span_ids:
        mention_idx = idx.index_of(mention_span_id)
        mention_section = idx.section_of(mention_span_id)

        # Expand ±context_window, clipping at array bounds and at section edges.
        start = max(0, mention_idx - context_window)
        end = min(last_block_index, mention_idx + context_window)
        for i in range(start, end + 1):
            if blocks[i].section_id == mention_section:
                selected.add(i)

    if not selected:
        # No blocks selected — emit an empty pack rather than failing. The
        # downstream extract_facts will abstain on empty allowed_span_ids.
        return "", {
            "candidate_id": candidate.candidate_id,
            "gall_maker_mention": candidate.gall_maker_mention,
            "allowed_span_ids": [],
        }

    sorted_indices = sorted(selected)
    text_parts = [f"[{blocks[i].span_id}] {blocks[i].text}" for i in sorted_indices]
    text = SPAN_SEPARATOR.join(text_parts)

    meta = {
        "candidate_id": candidate.candidate_id,
        "gall_maker_mention": candidate.gall_maker_mention,
        "allowed_span_ids": [blocks[i].span_id for i in sorted_indices],
    }
    return text, meta
