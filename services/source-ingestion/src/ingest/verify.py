"""Substring verification gate.

Deterministic, no LLM. For every evidence cell in a record, verify each
``{block_id, quote}`` pair: the quote must appear (within fuzzy tolerance)
inside the referenced normalized block's text.

If a single evidence in a cell fails, the cell's *value* is nulled and its
``support_status`` is set to ``evidence_substring_mismatch``. Surviving
evidence is enriched with absolute character offsets into the flat
normalized text — the offsets the review UI uses to highlight quotes in
context.

For ``TraitCell``, the gated field is ``suggested`` (the controlled-vocab
mapping claim). ``original`` is the source phrase and is left intact since
it's a source-of-truth excerpt, not a claim.

Default threshold: RapidFuzz ``partial_ratio >= 90``. Tunable per stage via
the pipeline YAML.
"""

from __future__ import annotations

from rapidfuzz import fuzz

from ingest.schemas import (
    Evidence,
    EvidenceCell,
    NormalizedBlock,
    SupportStatus,
    TraitCell,
    WarningEntry,
    WarningSeverity,
    WarningType,
)

# Default RapidFuzz partial_ratio threshold. 0-100 scale.
DEFAULT_MIN_SCORE: int = 90


def _index_blocks(blocks: list[NormalizedBlock]) -> dict[str, NormalizedBlock]:
    """O(1) lookup of normalized blocks by ``span_id``.

    The Evidence schema's ``block_id`` field carries the LLM's citation,
    which is the user-facing span_id (e.g. ``"S_0042"``) — that's what
    the prompt presents to the model. The NormalizedBlock has both a
    ``span_id`` and an unrelated ``block_id`` (PyMuPDF page+block, e.g.
    ``"p1-b3"``) which the LLM never sees, so we key by span_id here.
    """
    return {b.span_id: b for b in blocks}


def _gate_evidence(
    ev: Evidence,
    blocks_by_id: dict[str, NormalizedBlock],
    min_score: int,
) -> tuple[Evidence, float, bool]:
    """Gate one ``Evidence`` entry.

    Returns ``(possibly_enriched_evidence, score, passed)``.

    On pass: returns a new ``Evidence`` with ``char_start``/``char_end``
    overwritten with absolute offsets into the flat normalized text.
    On fail: returns the original evidence unchanged plus the score.
    """
    block = blocks_by_id.get(ev.block_id)
    if block is None:
        return ev, 0.0, False

    alignment = fuzz.partial_ratio_alignment(ev.quote, block.text)
    if alignment is None or alignment.score < min_score:
        return ev, float(alignment.score if alignment else 0.0), False

    abs_start = block.char_start + alignment.dest_start
    abs_end = block.char_start + alignment.dest_end
    enriched = ev.model_copy(
        update={
            "page": block.page,
            "char_start": abs_start,
            "char_end": abs_end,
        }
    )
    return enriched, float(alignment.score), True


def gate_cell(
    cell: EvidenceCell | TraitCell,
    blocks_by_id: dict[str, NormalizedBlock],
    *,
    field_path: str,
    record_id: str,
    min_score: int = DEFAULT_MIN_SCORE,
) -> tuple[EvidenceCell | TraitCell, list[WarningEntry]]:
    """Apply the substring gate to all evidence in a single cell.

    If ANY evidence in the cell fails, the cell's value (``value`` for
    ``EvidenceCell`` / ``ScientificNameCell``, ``suggested`` for ``TraitCell``)
    is nulled and ``support_status`` becomes ``evidence_substring_mismatch``.
    Per failed evidence, one ``WarningEntry`` is emitted.

    Surviving evidence is enriched with absolute offsets.

    Returns:
        ``(new_cell, warnings)``.
    """
    new_evidence: list[Evidence] = []
    warnings: list[WarningEntry] = []
    any_failed = False

    for ev in cell.evidence:
        gated, score, passed = _gate_evidence(ev, blocks_by_id, min_score)
        new_evidence.append(gated)
        if not passed:
            any_failed = True
            block = blocks_by_id.get(ev.block_id)
            warnings.append(
                WarningEntry(
                    type=WarningType.EVIDENCE_SUBSTRING_MISMATCH,
                    severity=WarningSeverity.WARNING,
                    record_id=record_id,
                    field_path=field_path,
                    detail={
                        "block_id": ev.block_id,
                        "claimed_quote": ev.quote,
                        "block_text": block.text if block else None,
                        "score": score,
                    },
                )
            )

    update: dict[str, object] = {"evidence": new_evidence}
    if any_failed:
        update["support_status"] = SupportStatus.EVIDENCE_SUBSTRING_MISMATCH
        # EvidenceCell / ScientificNameCell carry the claim in ``value``;
        # TraitCell carries it in ``suggested``. Null whichever applies.
        if isinstance(cell, TraitCell):
            update["suggested"] = []
        else:
            update["value"] = None

    return cell.model_copy(update=update), warnings
